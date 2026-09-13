#include "notehighlighter.h"

void NoteHighlighter::setDocument(QQuickTextDocument *doc) {
    if (m_quickDocument == doc)
        return;

    delete m_highlighter;
    m_highlighter = nullptr;
    m_quickDocument = doc;

    if (doc && doc->textDocument()) {
        // No need to guard this on m_background/etc. being non-empty:
        // MarkdownHighlighter::setColors() already early-returns when the
        // incoming values match its current (also default-empty) fields.
        m_highlighter = new MarkdownHighlighter(doc->textDocument());
        m_highlighter->setColors(m_background, m_foreground, m_accent);
    }

    emit documentChanged();
}

void NoteHighlighter::setColors(const QString &background, const QString &foreground,
                                 const QString &accent) {
    m_background = background;
    m_foreground = foreground;
    m_accent = accent;
    if (m_highlighter)
        m_highlighter->setColors(background, foreground, accent);
}
