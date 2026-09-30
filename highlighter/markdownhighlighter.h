#pragma once

// Live markdown styling for the journal, done the way omawrite does it.
//
// omawrite (/usr/bin/omawrite, Qt Quick) keeps the editor's document in plain
// markdown and installs a C++ QSyntaxHighlighter on it -- its symbol table has
// MarkdownHighlighter, QSyntaxHighlighter::setFormat, QFont::setPointSizeF,
// QTextCursor::mergeBlockFormat/joinPreviousEditBlock and
// QQuickTextDocument::textDocument, and notably QTextDocument::toMarkdown is
// absent: it never converts the document back, because the document's plain
// text *is* the source.
//
// What it looks like on screen (from a side-by-side of the same file in both
// apps) is the part worth copying exactly:
//   - the markers that shape a block stay *visible*, in a faint colour: `#`,
//     `##`, `-`, `>`. Only the ones inside a sentence disappear -- `**`, `*`,
//     `_`, and a link's `[`, `](url)`, leaving the label -- and that is where
//     the 1pt trick earns its keep.
//   - headings are bold and no larger than body text, at every level; a page
//     of writing must still read as a page of writing.
//   - blocks are set on a generous line height, which is what
//     mergeBlockFormat is for.
//   - inline code carries a soft fill *including* its backticks, which are
//     not dimmed. A fenced block gets nothing: there is no fence rule, so a
//     ``` line and the lines between are ordinary text.
// Nothing is ever deleted or rewritten, so the file on disk stays
// byte-for-byte what was typed.
//
// That is the whole reason this module exists. QML's only native live-markdown
// option is TextEdit.MarkdownText, which regenerates the markdown from the
// document on every read: measured on this machine it hard-wraps paragraphs at
// ~78 columns, rewrites `---` as `- - -` and drops two-space hard breaks. A
// journal file must survive being written to exactly as typed, so the
// highlighter route is the correct one, and a highlighter cannot be written in
// QML -- QQuickTextDocument::textDocument() is C++-only.
//
// Loaded as a plain file-based QML module sitting next to omvision.qml
// (MarkdownHighlight/qmldir + the built .so), so `qs -p ~/Code/omvision/
// omvision.qml` still launches the app with no environment set up. See
// highlighter/build.sh.

#include <QColor>
#include <QFont>
#include <QObject>
// Included, not forward-declared: the QML property below is a pointer to it,
// and Qt's meta-type system refuses a pointer to an incomplete type.
#include <QQuickTextDocument>
#include <QPointer>
#include <QRegularExpression>
#include <QSyntaxHighlighter>
#include <QTextCharFormat>
#include <QTextBlockUserData>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

class QTextDocument;

// Everything the QML side gets to say about how markdown is drawn. Colours
// come from Theme.qml (which solves them against the live omarchy theme), so
// nothing here invents a colour of its own.
struct MarkdownStyle {
  qreal basePointSize = 11.0;
  // Percent, QTextBlockFormat::ProportionalHeight. 100 is single-spaced.
  // The default is the 135 both users set explicitly (omvision's
  // JournalHighlight.qml and ompom's NoteHighlighterHost.qml). It used to
  // say 175, a value neither of them used, so a new user that left it unset
  // would have got a page spaced unlike either.
  int lineHeight = 135;
  QColor body;
  QColor marker;
  QColor accent;
  QColor quote;
  QColor code;
  QColor codeBackground;

  bool operator==(const MarkdownStyle& o) const {
    return basePointSize == o.basePointSize && lineHeight == o.lineHeight
        && body == o.body && marker == o.marker
        && accent == o.accent && quote == o.quote && code == o.code
        && codeBackground == o.codeBackground;
  }
  bool operator!=(const MarkdownStyle& o) const { return !(*this == o); }
};

// One goal tag as it was styled, kept on its block (MentionBlockData) so the
// QML side can draw the goal's title over it: see formatMentions().
struct MentionSpan {
  int start = 0;   // of the `@`, in the block
  QString slug;
  QString title;
  QFont font;      // the title's: the slug's own font after every rule
  qreal width = 0; // what the slug was stretched to

  bool operator==(const MentionSpan& o) const {
    return start == o.start && slug == o.slug && title == o.title
        && font == o.font && qFuzzyCompare(width + 1, o.width + 1);
  }
};

class MentionBlockData : public QTextBlockUserData {
public:
  QVector<MentionSpan> spans;
};

class MarkdownBlockHighlighter : public QSyntaxHighlighter {
  Q_OBJECT

public:
  explicit MarkdownBlockHighlighter(QTextDocument* document);

  void setStyle(const MarkdownStyle& style);
  // Goal slug -> title, the goals an `@slug` may name. Only these are
  // styled: an `@` in front of anything else (an address, a typo, a goal
  // since deleted) stays plain text, so what looks like a tag is always one
  // the journal can open.
  void setMentions(const QVariantMap& mentions);

signals:
  // A block's tags moved, appeared, went, or changed title or font.
  void spansChanged();

protected:
  void highlightBlock(const QString& text) override;

private:
  // A tag applyInline() found, `@` start and length, for formatMentions() to
  // finish once the block's other rules are done.
  using PendingMentions = QVector<QPair<int, int>>;
  // Everything highlightBlock() styles except the tags' titles, which have
  // to wait until every other rule has had its say on the slug's font.
  PendingMentions styleBlock(const QString& text);
  enum BlockState { StateNone = -1, StateFence = 1 };

  void rebuildFormats();
  // Inline spans (code, bold, italic, strike, links) over [from, end). `taken`
  // keeps later rules out of a span an earlier rule already claimed -- code
  // spans are matched first for exactly that reason, so `**` inside `` ` ``
  // stays literal. A tag in a heading (`inHeading`) is drawn as part of the
  // heading's own words, not as a tag.
  PendingMentions applyInline(const QString& text, int from, bool inHeading);
  // A marker that goes away: 1pt with its advance cancelled. Emphasis
  // markers and a link's brackets and target, and nothing else.
  void hideMarker(int start, int length);
  // Takes the colours off an input method's preedit while one is being
  // composed, so Qt Quick cannot paint them over the start of the line.
  void uncolourPreedit();
  // Generous line spacing, applied per block the way omawrite does it.
  void applyBlockSpacing();
  // Content formats are merged onto whatever is already there rather than
  // replacing it, so bold inside a heading stays heading-sized, and italic
  // inside bold keeps its weight.
  void mergeFormat(int start, int length, const QTextCharFormat& extra);

  MarkdownStyle m_style;
  QVariantMap m_mentions;
  // The line width the tags were last sized against; -1 until a tag is.
  qreal m_mentionLineWidth = -1;
  void formatMentions(const QString& text, const PendingMentions& pending);
  // One deferred rehighlight() however many style or goal changes land in
  // the same event-loop turn: goals load one at a time at startup, and each
  // would otherwise queue a pass of its own.
  void scheduleRehighlight();
  bool m_rehighlightQueued = false;
  bool m_inBlockFormat = false; // re-entrancy guard for applyBlockSpacing()
  QTextCharFormat m_marker;
  QTextCharFormat m_hidden;
  QTextCharFormat m_body;
  QTextCharFormat m_quote;
  QTextCharFormat m_code;
  QTextCharFormat m_listMarker;
  QTextCharFormat m_rule;
  QTextCharFormat m_link;
  QTextCharFormat m_mention;
  QTextCharFormat m_heading[7]; // 1..6
  QVector<bool> m_taken;
};

// The QML-facing handle: `document` is a TextEdit's `textDocument`, the rest
// are style inputs. Attaching is idempotent and detaching is safe -- the
// highlighter is parented to the QTextDocument, so a document that goes away
// takes its highlighter with it.
class MarkdownHighlighter : public QObject {
  Q_OBJECT

  Q_PROPERTY(QQuickTextDocument* document READ document WRITE setDocument NOTIFY documentChanged)
  Q_PROPERTY(qreal basePointSize READ basePointSize WRITE setBasePointSize NOTIFY styleChanged)
  Q_PROPERTY(int lineHeight READ lineHeight WRITE setLineHeight NOTIFY styleChanged)
  Q_PROPERTY(QColor bodyColor READ bodyColor WRITE setBodyColor NOTIFY styleChanged)
  Q_PROPERTY(QColor markerColor READ markerColor WRITE setMarkerColor NOTIFY styleChanged)
  Q_PROPERTY(QColor accentColor READ accentColor WRITE setAccentColor NOTIFY styleChanged)
  Q_PROPERTY(QColor quoteColor READ quoteColor WRITE setQuoteColor NOTIFY styleChanged)
  Q_PROPERTY(QColor codeColor READ codeColor WRITE setCodeColor NOTIFY styleChanged)
  Q_PROPERTY(QColor codeBackground READ codeBackground WRITE setCodeBackground NOTIFY styleChanged)
  // Omvision's own addition, not omawrite's: `@slug` names a goal, and this
  // maps each slug to the goal's title. Empty by default, so the ompom
  // overlay, which loads this module too, is unchanged.
  Q_PROPERTY(QVariantMap mentions READ mentions WRITE setMentions NOTIFY mentionsChanged)

public:
  explicit MarkdownHighlighter(QObject* parent = nullptr);

  QQuickTextDocument* document() const { return m_document; }
  void setDocument(QQuickTextDocument* document);

  qreal basePointSize() const { return m_style.basePointSize; }
  void setBasePointSize(qreal size);
  int lineHeight() const { return m_style.lineHeight; }
  void setLineHeight(int percent);
  QColor bodyColor() const { return m_style.body; }
  void setBodyColor(const QColor& c);
  QColor markerColor() const { return m_style.marker; }
  void setMarkerColor(const QColor& c);
  QColor accentColor() const { return m_style.accent; }
  void setAccentColor(const QColor& c);
  QColor quoteColor() const { return m_style.quote; }
  void setQuoteColor(const QColor& c);
  QColor codeColor() const { return m_style.code; }
  void setCodeColor(const QColor& c);
  QColor codeBackground() const { return m_style.codeBackground; }
  void setCodeBackground(const QColor& c);
  QVariantMap mentions() const { return m_mentions; }
  void setMentions(const QVariantMap& mentions);

  // Every tag in the document, where to draw its title and where a click
  // hits it: { slug, title, font, x (the title's), baseline, width, left
  // (the `@`'s), top, height (the line's) }, in the document's own
  // coordinates, which are the TextEdit's. Read from the current layout, so
  // ask again on mentionSpansChanged, which also fires on every reflow.
  Q_INVOKABLE QVariantList mentionSpans() const;

signals:
  void documentChanged();
  void styleChanged();
  void mentionsChanged();
  void mentionSpansChanged();

private:
  void applyStyle();

  QPointer<QQuickTextDocument> m_document;
  QPointer<MarkdownBlockHighlighter> m_highlighter;
  MarkdownStyle m_style;
  QVariantMap m_mentions;
};
