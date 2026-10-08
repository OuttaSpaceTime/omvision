#pragma once

#include <QObject>
#include <QPointer>
#include <QQuickTextDocument>
#include <qqml.h>

#include "markdownhighlighter.h"

// Bridges QML's TextEdit.textDocument (a QQuickTextDocument*, exposed
// precisely so external QSyntaxHighlighters can be attached from outside
// the TextEdit itself) to MarkdownHighlighter. This is the piece Omawrite
// doesn't need to expose separately since its C++ Backend class already
// owns both the document and the highlighter together.
class NoteHighlighter : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickTextDocument *document READ document WRITE setDocument NOTIFY documentChanged)
    // Percent, QTextBlockFormat::ProportionalHeight. QML's TextEdit has no
    // lineHeight of its own (verified -- the property simply does not
    // exist), and a writing surface set solid reads nothing like omawrite,
    // so the one piece of typography QML cannot do is done here.
    Q_PROPERTY(int lineHeight READ lineHeight WRITE setLineHeight NOTIFY lineHeightChanged)

public:
    explicit NoteHighlighter(QObject *parent = nullptr) : QObject(parent) {}

    QQuickTextDocument *document() const { return m_quickDocument; }
    void setDocument(QQuickTextDocument *doc);

    // Takes QML color values as strings (pass Color.xyz.toString()):
    // QColor's string parser accepts the "#AARRGGBB" format QML produces.
    Q_INVOKABLE void setColors(const QString &background, const QString &foreground,
                               const QString &accent);

    int lineHeight() const { return m_lineHeight; }
    void setLineHeight(int percent);

signals:
    void documentChanged();
    void lineHeightChanged();

private:
    // Applies m_lineHeight to every block that does not already carry it.
    // Cheap: a note is a handful of blocks, and a block that already agrees
    // is skipped, so after the first pass this is a no-op per keystroke.
    void applyLineHeight();

    QPointer<QQuickTextDocument> m_quickDocument;
    int m_lineHeight = 185;
    bool m_applyingLineHeight = false;
    MarkdownHighlighter *m_highlighter = nullptr;
    QString m_background;
    QString m_foreground;
    QString m_accent;
};
