#include "markdownhighlighter.h"

#include <QAbstractTextDocumentLayout>
#include <QFont>
#include <QFontMetricsF>
#include <QQuickTextDocument>
#include <QTextBlock>
#include <QTextLayout>
#include <QTextCursor>
#include <QTextDocument>
#include <QTimer>

namespace {

// Block-level shapes. All anchored, all tolerant of the up-to-three leading
// spaces CommonMark allows, and none of them is allowed to fail loudly: a line
// that matches nothing is simply body text, which is the common case in a
// journal.
const QRegularExpression& headingRe() {
  static const QRegularExpression re(QStringLiteral("^(#{1,6})([ \\t]+)(.*)$"));
  return re;
}
const QRegularExpression& quoteRe() {
  static const QRegularExpression re(QStringLiteral("^(\\s{0,3}>[ \\t]?)(.*)$"));
  return re;
}
const QRegularExpression& bulletRe() {
  static const QRegularExpression re(QStringLiteral("^(\\s*)([-*+](?:[ \\t]+|$))"));
  return re;
}
const QRegularExpression& orderedRe() {
  static const QRegularExpression re(QStringLiteral("^(\\s*)(\\d{1,9}[.)](?:[ \\t]+|$))"));
  return re;
}
const QRegularExpression& ruleRe() {
  static const QRegularExpression re(
      QStringLiteral("^\\s{0,3}((?:-[ \\t]*){3,}|(?:\\*[ \\t]*){3,}|(?:_[ \\t]*){3,})$"));
  return re;
}

// Inline spans, in the order they are applied. Code first: whatever is inside
// a code span is literal, so claiming its range first is what keeps `**` in
// `` `a ** b` `` from being read as bold. Links next, so the `*` in a URL is
// never emphasis. Then the emphasis family, strongest marker first.
//
// No strikethrough rule: omawrite does not recognise `~~`, and this is meant
// to read the same way it does.
struct InlineRule {
  const QRegularExpression& re;
  int openLength;   // marker characters before the content
  int closeLength;  // marker characters after it, when fixed
  enum Kind { Code, Link, Mention, Bold, Italic } kind;
};

const QRegularExpression& codeRe() {
  static const QRegularExpression re(QStringLiteral("`([^`\\n]+)`"));
  return re;
}
const QRegularExpression& linkRe() {
  static const QRegularExpression re(QStringLiteral("\\[([^\\]\\n]*)\\]\\(([^)\\n]*)\\)"));
  return re;
}
// `@slug`, the journal's goal tag. The slug grammar is goal-files.md's (lower
// case, digits, single hyphens, never ending in one, so `@learn-rust.` stops
// before the full stop). Not after a word character or another `@`, which
// keeps `me@example.com` out. The QML side never re-reads the text for tags:
// it hit-tests the spans this finds (mentionSpans()).
const QRegularExpression& mentionRe() {
  static const QRegularExpression re(QStringLiteral("(?<![\\w@])@([a-z0-9]+(?:-[a-z0-9]+)*)(?![\\w-])"));
  return re;
}
const QRegularExpression& boldStarRe() {
  static const QRegularExpression re(QStringLiteral("\\*\\*(\\S(?:[^\\n]*?\\S)?)\\*\\*"));
  return re;
}
const QRegularExpression& boldUnderRe() {
  static const QRegularExpression re(QStringLiteral("(?<![\\w_])__(\\S(?:[^\\n]*?\\S)?)__(?![\\w_])"));
  return re;
}
const QRegularExpression& italicStarRe() {
  static const QRegularExpression re(QStringLiteral("(?<![\\w*])\\*(\\S(?:[^\\n*]*?\\S)?)\\*(?!\\*)"));
  return re;
}
const QRegularExpression& italicUnderRe() {
  static const QRegularExpression re(QStringLiteral("(?<![\\w_])_(\\S(?:[^\\n_]*?\\S)?)_(?![\\w_])"));
  return re;
}

} // namespace

MarkdownBlockHighlighter::MarkdownBlockHighlighter(QTextDocument* document)
    : QSyntaxHighlighter(document) {
  rebuildFormats();
  // A tag's gap is capped at the line's width (formatMentions()), and the
  // first pass often runs before the TextEdit has its final width. Nothing
  // re-highlights on a reflow by itself, so a width the tags were not sized
  // for does -- only the blocks holding tags, since nothing else depends on
  // the width, and the column animates its width when the rail slides. The
  // size signal also fires on every edit that adds a line; the width check
  // keeps that to a comparison.
  connect(document->documentLayout(), &QAbstractTextDocumentLayout::documentSizeChanged,
          this, [this]() {
            if (m_mentionLineWidth < 0 || !this->document()) return;
            if (qFuzzyCompare(this->document()->textWidth(), m_mentionLineWidth)) return;
            m_mentionLineWidth = this->document()->textWidth();
            QTimer::singleShot(0, this, [this]() {
              if (!this->document()) return;
              for (QTextBlock b = this->document()->begin(); b.isValid(); b = b.next()) {
                const auto* data = dynamic_cast<const MentionBlockData*>(b.userData());
                if (data && !data->spans.isEmpty()) rehighlightBlock(b);
              }
            });
          });
}

void MarkdownBlockHighlighter::setStyle(const MarkdownStyle& style) {
  if (m_style == style) return;
  m_style = style;
  rebuildFormats();
  // Never from inside highlightBlock() -- rehighlight() re-enters the
  // highlighter, which Qt documents as invalid there. Style changes arrive
  // from QML property writes, so a deferred call is enough to keep the two
  // paths from ever meeting.
  scheduleRehighlight();
}

void MarkdownBlockHighlighter::setMentions(const QVariantMap& mentions) {
  if (m_mentions == mentions) return;
  m_mentions = mentions;
  scheduleRehighlight();
}

void MarkdownBlockHighlighter::scheduleRehighlight() {
  if (m_rehighlightQueued) return;
  m_rehighlightQueued = true;
  QTimer::singleShot(0, this, [this]() {
    m_rehighlightQueued = false;
    rehighlight();
  });
}

void MarkdownBlockHighlighter::rebuildFormats() {
  const qreal base = m_style.basePointSize > 0 ? m_style.basePointSize : 11.0;

  // Two different treatments, and which marker gets which is the whole look:
  //
  //   dim    -- a heading's `#`s, a list's `-` or `1.`, a quote's `>`, and
  //             a `---` rule. These hold the left edge of the text. Hiding
  //             them would pull every heading and every bullet a few
  //             characters leftward as you typed, so they stay, faintly.
  //             Inline code's backticks are not among them: they take the
  //             code's own format, undimmed (see the Code rule below), and
  //             a ``` line has no rule at all (see styleBlock).
  //   hidden -- `**`, `*`, `_`, and a link's `[` and `](url)`. These sit
  //             inside a sentence, where they are noise rather than
  //             structure. 1pt and transparent: still in the document, still
  //             in the file, still steppable with the arrow keys.
  m_marker = QTextCharFormat();
  if (m_style.marker.isValid()) m_marker.setForeground(m_style.marker);

  m_hidden = QTextCharFormat();
  m_hidden.setFontPointSize(1.0);
  m_hidden.setForeground(QColor(0, 0, 0, 0));
  // 1pt alone still leaves a couple of pixels of advance per character --
  // visible as a smudge after a link. omawrite's own highlighter cancels that
  // advance with negative absolute letter-spacing (and notes that shrinking
  // the size further deadlocks Qt's font metrics engine on some platforms).
  {
    QFont hiddenFont = document() ? document()->defaultFont() : QFont();
    hiddenFont.setPointSizeF(1.0);
    const qreal charWidth = QFontMetricsF(hiddenFont).horizontalAdvance(QLatin1Char('['));
    m_hidden.setFontLetterSpacingType(QFont::AbsoluteSpacing);
    m_hidden.setFontLetterSpacing(-charWidth);
  }

  m_body = QTextCharFormat();
  if (m_style.body.isValid()) m_body.setForeground(m_style.body);

  m_quote = QTextCharFormat();
  m_quote.setFontItalic(true);
  if (m_style.quote.isValid()) m_quote.setForeground(m_style.quote);

  // Inline code only. A fenced block gets no fill: there is no fence rule,
  // so its ``` lines and everything between them are ordinary text, which
  // is what omawrite shows.
  m_code = QTextCharFormat();
  if (m_style.code.isValid()) m_code.setForeground(m_style.code);
  if (m_style.codeBackground.isValid()) m_code.setBackground(m_style.codeBackground);

  m_listMarker = m_marker;
  m_rule = m_marker;

  m_link = QTextCharFormat();
  m_link.setFontUnderline(true);
  if (m_style.accent.isValid()) m_link.setForeground(m_style.accent);

  // A tag is accent without the underline: it opens a goal in this app, it
  // is not a web link, and the `@` stays visible because it is the only
  // thing marking the word as a tag.
  m_mention = QTextCharFormat();
  if (m_style.accent.isValid()) m_mention.setForeground(m_style.accent);

  // Bold, and *not* bigger, at every level -- omawrite's own heading format
  // sets weight and colour and nothing else, which is why a page of its
  // headings still reads as a page of writing rather than a document outline.
  for (int level = 1; level <= 6; ++level) {
    QTextCharFormat f;
    f.setFontWeight(QFont::Bold);
    if (m_style.body.isValid()) f.setForeground(m_style.body);
    m_heading[level] = f;
  }
  Q_UNUSED(base);
}

// Line spacing, per block, the way omawrite does it -- QTextCursor +
// joinPreviousEditBlock/endEditBlock, so the change merges into the user's own
// undo step rather than becoming an undo of its own. Only touched when it is
// actually wrong, so the edit is a no-op on every keystroke after the first,
// and guarded against re-entering itself through the rehighlight that a block
// format change triggers.
void MarkdownBlockHighlighter::applyBlockSpacing() {
  if (m_inBlockFormat) return;
  if (m_style.lineHeight <= 0) return;

  QTextBlock block = currentBlock();
  if (!block.isValid()) return;

  const QTextBlockFormat current = block.blockFormat();
  if (current.lineHeightType() == QTextBlockFormat::ProportionalHeight
      && qFuzzyCompare(current.lineHeight(), qreal(m_style.lineHeight))) {
    return;
  }

  m_inBlockFormat = true;
  QTextBlockFormat wanted;
  wanted.setLineHeight(m_style.lineHeight, QTextBlockFormat::ProportionalHeight);
  QTextCursor cursor(block);
  cursor.joinPreviousEditBlock();
  cursor.mergeBlockFormat(wanted);
  cursor.endEditBlock();
  m_inBlockFormat = false;
}

void MarkdownBlockHighlighter::hideMarker(int start, int length) {
  if (length <= 0) return;
  setFormat(start, length, m_hidden);
}

void MarkdownBlockHighlighter::mergeFormat(int start, int length, const QTextCharFormat& extra) {
  if (length <= 0) return;
  QTextCharFormat f = format(start);
  f.merge(extra);
  setFormat(start, length, f);
}

void MarkdownBlockHighlighter::highlightBlock(const QString& text) {
  uncolourPreedit();
  formatMentions(text, styleBlock(text));
}

// While a compose sequence or other input method is mid-word, the text it
// has not committed yet (fcitx5 shows `·` after Compose) sits in the block's
// layout as a preedit, and fcitx5 colours it with the system highlight. Two
// parts of Qt 6.11 disagree about that colour. QSyntaxHighlighter keeps the
// preedit's format ranges and puts them *first* in the layout's list, ahead
// of the ones this highlighter sets from position 0. QQuickTextNodeEngine::
// mergeFormats, which paints the list, assumes it is sorted by position:
// meeting a coloured range that starts before the preedit's end, it merges
// the two and moves the preedit's highlight to that range's start. So on any
// line with an earlier coloured character -- a tag's `@`, a list's `-`, a
// link -- a blue box sat on that character while composing, which reads as
// the cursor jumping to the start of the line. The text and the real cursor
// never moved.
//
// mergeFormats only takes ranges that carry a colour, so the preedit's are
// taken off (its other properties, an underline say, stay) and it draws in
// the text's own colour at the cursor. Sorting the list instead was
// rejected: it is rebuilt after highlightBlock() returns, and re-sorting it
// later would mean marking the block dirty, which runs the highlighter
// again and puts the preedit first once more.
void MarkdownBlockHighlighter::uncolourPreedit() {
  QTextLayout* layout = currentBlock().layout();
  if (!layout) return;
  const int start = layout->preeditAreaPosition();
  const int length = layout->preeditAreaText().length();
  if (length == 0) return;

  QList<QTextLayout::FormatRange> ranges = layout->formats();
  bool changed = false;
  for (QTextLayout::FormatRange& r : ranges) {
    // The same test QSyntaxHighlighter uses to tell the preedit's ranges
    // from the ones it is about to replace.
    if (r.start < start || r.start + r.length > start + length) continue;
    if (!r.format.hasProperty(QTextFormat::ForegroundBrush)
        && !r.format.hasProperty(QTextFormat::BackgroundBrush)) continue;
    r.format.clearForeground();
    r.format.clearBackground();
    changed = true;
  }
  if (changed) layout->setFormats(ranges);
}

MarkdownBlockHighlighter::PendingMentions MarkdownBlockHighlighter::styleBlock(const QString& text) {
  const int len = text.length();
  applyBlockSpacing();

  // No fenced-code rule: omawrite has none, so a ``` line is ordinary text
  // and there is no multi-line state to carry. Left as StateNone for the
  // same reason.
  setCurrentBlockState(StateNone);
  if (len == 0) return {};

  m_taken.assign(len, false);

  // ---- block shape ---------------------------------------------------------
  int bodyStart = 0;

  const QRegularExpressionMatch heading = headingRe().match(text);
  const QRegularExpressionMatch quote = quoteRe().match(text);
  const QRegularExpressionMatch rule = ruleRe().match(text);

  if (rule.hasMatch()) {
    setFormat(0, len, m_rule);
    return {};
  }

  if (heading.hasMatch()) {
    const int level = qBound(1, heading.capturedLength(1), 6);
    setFormat(heading.capturedStart(3), len - heading.capturedStart(3), m_heading[level]);
    // The hashes go last so the content format above cannot overwrite them,
    // and they keep the document's own size and weight -- a faint `#`, not a
    // faint bold `#`.
    setFormat(heading.capturedStart(1), heading.capturedLength(1), m_marker);
    bodyStart = heading.capturedStart(3);
  } else if (quote.hasMatch()) {
    setFormat(quote.capturedStart(2), len - quote.capturedStart(2), m_quote);
    setFormat(quote.capturedStart(1), quote.capturedLength(1), m_marker);
    bodyStart = quote.capturedStart(2);
  } else {
    // List markers stay visible, only dimmed, like a heading's `#`. Hiding
    // them the way `**` is hidden would leave a list looking like loose
    // lines -- the bullet is structure you are meant to see, not syntax you
    // are meant to forget.
    const QRegularExpressionMatch bullet = bulletRe().match(text);
    const QRegularExpressionMatch ordered = orderedRe().match(text);
    if (bullet.hasMatch()) {
      setFormat(bullet.capturedStart(2), bullet.capturedLength(2), m_listMarker);
      bodyStart = bullet.capturedEnd(2);
    } else if (ordered.hasMatch()) {
      setFormat(ordered.capturedStart(2), ordered.capturedLength(2), m_listMarker);
      bodyStart = ordered.capturedEnd(2);
    }
  }

  for (int i = 0; i < bodyStart && i < len; ++i) m_taken[i] = true;

  return applyInline(text, bodyStart, heading.hasMatch());
}

MarkdownBlockHighlighter::PendingMentions
MarkdownBlockHighlighter::applyInline(const QString& text, int from, bool inHeading) {
  PendingMentions mentions;
  const int len = text.length();
  if (from >= len) return mentions;
  // No goals (the ompom overlay's case) or no `@` on the line: the tag rule
  // cannot match, so its lookbehind scan is skipped.
  const bool mayMention = !m_mentions.isEmpty() && text.contains(QLatin1Char('@'));

  static const InlineRule rules[] = {
      {codeRe(), 1, 1, InlineRule::Code},
      {linkRe(), 0, 0, InlineRule::Link},
      {mentionRe(), 0, 0, InlineRule::Mention},
      {boldStarRe(), 2, 2, InlineRule::Bold},
      {boldUnderRe(), 2, 2, InlineRule::Bold},
      {italicStarRe(), 1, 1, InlineRule::Italic},
      {italicUnderRe(), 1, 1, InlineRule::Italic},
  };

  for (const InlineRule& rule : rules) {
    if (rule.kind == InlineRule::Mention && !mayMention) continue;
    QRegularExpressionMatchIterator it = rule.re.globalMatch(text, from);
    while (it.hasNext()) {
      const QRegularExpressionMatch m = it.next();
      const int start = m.capturedStart(0);
      const int length = m.capturedLength(0);
      if (start < from) continue;

      bool overlaps = false;
      for (int i = start; i < start + length; ++i) {
        if (m_taken[i]) { overlaps = true; break; }
      }
      if (overlaps) continue;
      // An unknown slug claims nothing, so the text around it is read as
      // though the `@` were any other character.
      if (rule.kind == InlineRule::Mention && !m_mentions.contains(m.captured(1))) continue;
      for (int i = start; i < start + length; ++i) m_taken[i] = true;

      if (rule.kind == InlineRule::Mention) {
        // The `@` now; the slug once bold and italic have been applied
        // over it, since the title is drawn in whatever font it ends up in.
        // The accent everywhere, heading or not: it is what says "this is
        // a goal, click it". Merged, so a heading keeps its weight.
        mergeFormat(start, 1, m_mention);
        if (inHeading) hideMarker(start, 1);
        mentions.append({start, length});
        continue;
      }

      const int contentStart = m.capturedStart(1);
      const int contentLength = m.capturedLength(1);

      if (rule.kind == InlineRule::Link) {
        // [label](url): the label is what you read, everything else is
        // plumbing, and plumbing is the one inline thing that disappears.
        mergeFormat(contentStart, contentLength, m_link);
        hideMarker(start, contentStart - start);                       // "["
        hideMarker(m.capturedEnd(1), (start + length) - m.capturedEnd(1)); // "](url)"
        continue;
      }

      if (rule.kind == InlineRule::Code) {
        // One format across the whole span, backticks included and not
        // dimmed -- exactly what omawrite does.
        mergeFormat(start, length, m_code);
        continue;
      }

      QTextCharFormat extra;
      if (rule.kind == InlineRule::Bold) extra.setFontWeight(QFont::Bold);
      else extra.setFontItalic(true);
      mergeFormat(contentStart, contentLength, extra);
      hideMarker(start, rule.openLength);
      hideMarker(contentStart + contentLength, rule.closeLength);
    }
  }
  return mentions;
}

// A tag reads as the goal's current title, not as the slug the file holds:
// `@learn-rust` shows `@Learn Rust`, and after the goal is renamed, its new
// title. A highlighter can restyle characters but never change them, so the
// slug is made invisible and exactly as wide as the title, and the QML side
// draws the title over that gap (mentionSpans()). All the width goes on the
// slug's first character, as letter spacing; the rest shrinks to nothing the
// way a hidden marker does. One wide character cannot be split by a line
// break, where a slug stretched evenly could break after any hyphen and
// leave the drawn title hanging over the end of the line.
//
// Styling the slug as words instead (hyphens transparent, the heading's
// capitals through AllUppercase) was the first version. It kept showing the
// name the goal had when it was tagged, and a slug that lost characters
// ("Diät" is `@di-t`) read "Di t".
//
// In a heading the `@` is hidden, so the title reads as part of the
// heading's own words; in body text it stays, in the accent.
void MarkdownBlockHighlighter::formatMentions(const QString& text, const PendingMentions& pending) {
  QVector<MentionSpan> spans;
  const QFont base = document() ? document()->defaultFont() : QFont();
  const qreal lineWidth = document() ? document()->textWidth() : -1;
  if (!pending.isEmpty()) m_mentionLineWidth = lineWidth;
  for (const auto& [start, length] : pending) {
    MentionSpan span;
    span.start = start;
    span.slug = text.mid(start + 1, length - 1);
    span.title = m_mentions.value(span.slug).toString();
    if (span.title.isEmpty()) span.title = span.slug;

    QTextCharFormat box = format(start + 1);
    span.font = box.font().resolve(base);
    const QFontMetricsF fm(span.font);
    span.width = fm.horizontalAdvance(span.title);
    // A title longer than the line is cut short (the QML side elides it)
    // rather than pushed past the page's right edge.
    if (lineWidth > 0) span.width = qMin(span.width, lineWidth - fm.horizontalAdvance(QLatin1Char('@')));

    box.setForeground(QColor(0, 0, 0, 0));
    box.setFontLetterSpacingType(QFont::AbsoluteSpacing);
    box.setFontLetterSpacing(span.width - fm.horizontalAdvance(text.at(start + 1)));
    setFormat(start + 1, 1, box);
    hideMarker(start + 2, length - 2);
    spans.append(span);
  }

  // Kept on the block only when there is something to keep or to clear, so
  // the common block, with no tags ever, carries no data at all.
  auto* data = dynamic_cast<MentionBlockData*>(currentBlockUserData());
  if (data ? data->spans == spans : spans.isEmpty()) return;
  if (!data) {
    data = new MentionBlockData;
    setCurrentBlockUserData(data);
  }
  data->spans = spans;
  emit spansChanged();
}

// ---- QML handle -------------------------------------------------------------

MarkdownHighlighter::MarkdownHighlighter(QObject* parent) : QObject(parent) {}

void MarkdownHighlighter::setDocument(QQuickTextDocument* document) {
  if (m_document == document) return;

  // The old highlighter is parented to the old QTextDocument; delete it
  // explicitly so two highlighters never sit on one document, and let QPointer
  // cover the case where the document died first and took it along.
  if (m_highlighter) delete m_highlighter.data();
  m_highlighter = nullptr;

  m_document = document;
  if (m_document && m_document->textDocument()) {
    m_highlighter = new MarkdownBlockHighlighter(m_document->textDocument());
    m_highlighter->setStyle(m_style);
    m_highlighter->setMentions(m_mentions);
    connect(m_highlighter, &MarkdownBlockHighlighter::spansChanged,
            this, &MarkdownHighlighter::mentionSpansChanged);
    // A reflow (a new width, a line added above) moves tags without
    // restyling them, so the spans are stale then too.
    connect(m_document->textDocument()->documentLayout(),
            &QAbstractTextDocumentLayout::documentSizeChanged,
            this, &MarkdownHighlighter::mentionSpansChanged);
  }
  emit documentChanged();
  emit mentionSpansChanged();
}

void MarkdownHighlighter::setMentions(const QVariantMap& mentions) {
  if (m_mentions == mentions) return;
  m_mentions = mentions;
  if (m_highlighter) m_highlighter->setMentions(m_mentions);
  emit mentionsChanged();
}

QVariantList MarkdownHighlighter::mentionSpans() const {
  QVariantList out;
  QTextDocument* doc = m_document ? m_document->textDocument() : nullptr;
  if (!doc) return out;
  QAbstractTextDocumentLayout* layout = doc->documentLayout();
  for (QTextBlock block = doc->begin(); block.isValid(); block = block.next()) {
    const auto* data = dynamic_cast<const MentionBlockData*>(block.userData());
    if (!data || data->spans.isEmpty()) continue;
    // Asked first: it lays the block out if it is not yet.
    const QRectF blockRect = layout->blockBoundingRect(block);
    const QTextLayout* textLayout = block.layout();
    if (!textLayout) continue;
    for (const MentionSpan& span : data->spans) {
      // The title starts where the slug does, just after the `@`.
      const int at = span.start + 1;
      const QTextLine line = textLayout->lineForTextPosition(at);
      if (!line.isValid()) continue;
      out.append(QVariantMap{
          {QStringLiteral("slug"), span.slug},
          {QStringLiteral("title"), span.title},
          {QStringLiteral("font"), span.font},
          {QStringLiteral("x"), blockRect.x() + line.cursorToX(at)},
          {QStringLiteral("baseline"), blockRect.y() + line.y() + line.ascent()},
          {QStringLiteral("width"), span.width},
          {QStringLiteral("left"), blockRect.x() + line.cursorToX(span.start)},
          {QStringLiteral("top"), blockRect.y() + line.y()},
          {QStringLiteral("height"), line.height()},
      });
    }
  }
  return out;
}

void MarkdownHighlighter::applyStyle() {
  if (m_highlighter) m_highlighter->setStyle(m_style);
  emit styleChanged();
}

void MarkdownHighlighter::setBasePointSize(qreal size) {
  if (qFuzzyCompare(m_style.basePointSize, size)) return;
  m_style.basePointSize = size;
  applyStyle();
}

void MarkdownHighlighter::setLineHeight(int percent) {
  if (m_style.lineHeight == percent) return;
  m_style.lineHeight = percent;
  applyStyle();
}

void MarkdownHighlighter::setBodyColor(const QColor& c) {
  if (m_style.body == c) return;
  m_style.body = c;
  applyStyle();
}

void MarkdownHighlighter::setMarkerColor(const QColor& c) {
  if (m_style.marker == c) return;
  m_style.marker = c;
  applyStyle();
}

void MarkdownHighlighter::setAccentColor(const QColor& c) {
  if (m_style.accent == c) return;
  m_style.accent = c;
  applyStyle();
}

void MarkdownHighlighter::setQuoteColor(const QColor& c) {
  if (m_style.quote == c) return;
  m_style.quote = c;
  applyStyle();
}

void MarkdownHighlighter::setCodeColor(const QColor& c) {
  if (m_style.code == c) return;
  m_style.code = c;
  applyStyle();
}

void MarkdownHighlighter::setCodeBackground(const QColor& c) {
  if (m_style.codeBackground == c) return;
  m_style.codeBackground = c;
  applyStyle();
}
