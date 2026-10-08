#include "notehighlighter.h"

#include <QTextBlock>
#include <QTextCursor>
#include <QTextDocument>

void NoteHighlighter::setDocument(QQuickTextDocument *doc) {
    if (m_quickDocument == doc)
        return;

    // Not manually deleted: QSyntaxHighlighter's own constructor parents
    // the highlighter to the QTextDocument it's given, so Qt's ordinary
    // parent-child ownership already deletes it whenever that document is
    // destroyed. Deleting it here too meant two independent mechanisms
    // could free the same object -- defense in depth against a possible
    // double-free, cheap regardless of whether it was the actual cause of
    // the crash this plugin once caused (see native/README.md).
    m_highlighter = nullptr;
    m_quickDocument = doc;

    if (doc && doc->textDocument()) {
        // No need to guard this on m_background/etc. being non-empty:
        // MarkdownHighlighter::setColors() already early-returns when the
        // incoming values match its current (also default-empty) fields.
        m_highlighter = new MarkdownHighlighter(doc->textDocument());
        m_highlighter->setColors(m_background, m_foreground, m_accent);

        // Line height is a *block* format, which a QSyntaxHighlighter cannot
        // set (setFormat only reaches character formats), so it is applied
        // from out here on every content change -- the same mechanism
        // omawrite's own editor uses QTextCursor::mergeBlockFormat for.
        QObject::connect(doc->textDocument(), &QTextDocument::contentsChanged,
                         this, &NoteHighlighter::applyLineHeight);
        applyLineHeight();
    }

    emit documentChanged();
}

void NoteHighlighter::setLineHeight(int percent) {
    if (m_lineHeight == percent)
        return;
    m_lineHeight = percent;
    applyLineHeight();
    emit lineHeightChanged();
}

void NoteHighlighter::applyLineHeight() {
    // Re-entrancy guard: setting a block format is itself a document change,
    // which would call straight back in here.
    if (m_applyingLineHeight || m_lineHeight <= 0)
        return;
    if (!m_quickDocument || !m_quickDocument->textDocument())
        return;

    QTextDocument *document = m_quickDocument->textDocument();
    m_applyingLineHeight = true;
    for (QTextBlock block = document->begin(); block.isValid(); block = block.next()) {
        const QTextBlockFormat current = block.blockFormat();
        if (current.lineHeightType() == QTextBlockFormat::ProportionalHeight
                && qFuzzyCompare(current.lineHeight(), qreal(m_lineHeight)))
            continue;

        QTextBlockFormat wanted;
        wanted.setLineHeight(m_lineHeight, QTextBlockFormat::ProportionalHeight);
        QTextCursor cursor(block);
        // Folds into the user's own undo step rather than becoming an undo
        // of its own.
        cursor.joinPreviousEditBlock();
        cursor.mergeBlockFormat(wanted);
        cursor.endEditBlock();
    }
    m_applyingLineHeight = false;
}

void NoteHighlighter::setColors(const QString &background, const QString &foreground,
                                 const QString &accent) {
    m_background = background;
    m_foreground = foreground;
    m_accent = accent;
    if (m_highlighter)
        m_highlighter->setColors(background, foreground, accent);
}
