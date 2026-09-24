#include "markdownhighlighter.h"

#include <QFont>
#include <QFontMetricsF>
#include <QQuickTextDocument>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextDocument>
#include <QTimer>

namespace {

// Block-level shapes. All anchored, all tolerant of the up-to-three leading
// spaces CommonMark allows, and none of them is allowed to fail loudly: a line
// that matches nothing is simply body text, which is the common case in a
// journal.
const QRegularExpression& fenceRe() {
  static const QRegularExpression re(QStringLiteral("^\\s{0,3}(```|~~~)"));
  return re;
}
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
  enum Kind { Code, Link, Bold, Italic } kind;
};

const QRegularExpression& codeRe() {
  static const QRegularExpression re(QStringLiteral("`([^`\\n]+)`"));
  return re;
}
const QRegularExpression& linkRe() {
  static const QRegularExpression re(QStringLiteral("\\[([^\\]\\n]*)\\]\\(([^)\\n]*)\\)"));
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
}

void MarkdownBlockHighlighter::setStyle(const MarkdownStyle& style) {
  if (m_style == style) return;
  m_style = style;
  rebuildFormats();
  // Never from inside highlightBlock() -- rehighlight() re-enters the
  // highlighter, which Qt documents as invalid there. Style changes arrive
  // from QML property writes, so a deferred call is enough to keep the two
  // paths from ever meeting.
  QTimer::singleShot(0, this, [this]() { rehighlight(); });
}

void MarkdownBlockHighlighter::rebuildFormats() {
  const qreal base = m_style.basePointSize > 0 ? m_style.basePointSize : 11.0;

  // Two different treatments, and which marker gets which is the whole look:
  //
  //   dim    -- `#`, `-`, `>`, the backticks around code, the fence lines.
  //             These hold the left edge of the text. Hiding them would pull
  //             every heading and every bullet a few characters leftward as
  //             you typed, so they stay, faintly.
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

  // Inline code only. A fenced block gets no fill -- its fences are dimmed
  // and its lines left as ordinary text, which is what omawrite shows.
  m_code = QTextCharFormat();
  if (m_style.code.isValid()) m_code.setForeground(m_style.code);
  if (m_style.codeBackground.isValid()) m_code.setBackground(m_style.codeBackground);

  m_listMarker = m_marker;
  m_rule = m_marker;

  m_link = QTextCharFormat();
  m_link.setFontUnderline(true);
  if (m_style.accent.isValid()) m_link.setForeground(m_style.accent);

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
  const int len = text.length();
  applyBlockSpacing();

  // No fenced-code rule: omawrite has none, so a ``` line is ordinary text
  // and there is no multi-line state to carry. Left as StateNone for the
  // same reason.
  setCurrentBlockState(StateNone);
  if (len == 0) return;

  m_taken.assign(len, false);

  // ---- block shape ---------------------------------------------------------
  int bodyStart = 0;

  const QRegularExpressionMatch heading = headingRe().match(text);
  const QRegularExpressionMatch quote = quoteRe().match(text);
  const QRegularExpressionMatch rule = ruleRe().match(text);

  if (rule.hasMatch()) {
    setFormat(0, len, m_rule);
    return;
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
    // List markers stay visible, only dimmed. Hiding them the way `#` is
    // hidden would leave a list looking like loose lines -- the bullet is
    // structure you are meant to see, not syntax you are meant to forget.
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

  applyInline(text, bodyStart);
}

void MarkdownBlockHighlighter::applyInline(const QString& text, int from) {
  const int len = text.length();
  if (from >= len) return;

  static const InlineRule rules[] = {
      {codeRe(), 1, 1, InlineRule::Code},
      {linkRe(), 0, 0, InlineRule::Link},
      {boldStarRe(), 2, 2, InlineRule::Bold},
      {boldUnderRe(), 2, 2, InlineRule::Bold},
      {italicStarRe(), 1, 1, InlineRule::Italic},
      {italicUnderRe(), 1, 1, InlineRule::Italic},
  };

  for (const InlineRule& rule : rules) {
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
      for (int i = start; i < start + length; ++i) m_taken[i] = true;

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
  }
  emit documentChanged();
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
