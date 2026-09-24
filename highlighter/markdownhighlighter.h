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
//   - syntax markers stay *visible*, in a faint colour: `#`, `##`, `-`, `>`,
//     the backticks around code and the fence lines are all still there. Only
//     a link's `[`, `](url)` disappear, leaving the label -- that is where the
//     1pt trick earns its keep.
//   - headings are bold and barely larger than body text (h1 a step, h2 a
//     hair); a page of writing must still read as a page of writing.
//   - blocks are set on a generous line height, which is what
//     mergeBlockFormat is for.
//   - inline code carries a soft fill *including* its backticks; a fenced
//     block does not -- its fences are dimmed and its lines left alone.
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
#include <QObject>
// Included, not forward-declared: the QML property below is a pointer to it,
// and Qt's meta-type system refuses a pointer to an incomplete type.
#include <QQuickTextDocument>
#include <QPointer>
#include <QRegularExpression>
#include <QSyntaxHighlighter>
#include <QTextCharFormat>
#include <QVector>

class QTextDocument;

// Everything the QML side gets to say about how markdown is drawn. Colours
// come from Theme.qml (which solves them against the live omarchy theme), so
// nothing here invents a colour of its own.
struct MarkdownStyle {
  qreal basePointSize = 11.0;
  // Percent, QTextBlockFormat::ProportionalHeight. 100 is single-spaced.
  int lineHeight = 175;
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

class MarkdownBlockHighlighter : public QSyntaxHighlighter {
  Q_OBJECT

public:
  explicit MarkdownBlockHighlighter(QTextDocument* document);

  void setStyle(const MarkdownStyle& style);

protected:
  void highlightBlock(const QString& text) override;

private:
  enum BlockState { StateNone = -1, StateFence = 1 };

  void rebuildFormats();
  // Inline spans (code, bold, italic, strike, links) over [from, end). `taken`
  // keeps later rules out of a span an earlier rule already claimed -- code
  // spans are matched first for exactly that reason, so `**` inside `` ` ``
  // stays literal.
  void applyInline(const QString& text, int from);
  // A marker that goes away: 1pt with its advance cancelled. Emphasis
  // markers and a link's brackets and target, and nothing else.
  void hideMarker(int start, int length);
  // Generous line spacing, applied per block the way omawrite does it.
  void applyBlockSpacing();
  // Content formats are merged onto whatever is already there rather than
  // replacing it, so bold inside a heading stays heading-sized, and italic
  // inside bold keeps its weight.
  void mergeFormat(int start, int length, const QTextCharFormat& extra);

  MarkdownStyle m_style;
  bool m_inBlockFormat = false; // re-entrancy guard for applyBlockSpacing()
  QTextCharFormat m_marker;
  QTextCharFormat m_hidden;
  QTextCharFormat m_body;
  QTextCharFormat m_quote;
  QTextCharFormat m_code;
  QTextCharFormat m_listMarker;
  QTextCharFormat m_rule;
  QTextCharFormat m_link;
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

signals:
  void documentChanged();
  void styleChanged();

private:
  void applyStyle();

  QPointer<QQuickTextDocument> m_document;
  QPointer<MarkdownBlockHighlighter> m_highlighter;
  MarkdownStyle m_style;
};
