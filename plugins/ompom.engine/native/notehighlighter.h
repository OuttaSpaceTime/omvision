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

public:
    explicit NoteHighlighter(QObject *parent = nullptr) : QObject(parent) {}

    QQuickTextDocument *document() const { return m_quickDocument; }
    void setDocument(QQuickTextDocument *doc);

    // Takes QML color values as strings (pass Color.xyz.toString()):
    // QColor's string parser accepts the "#AARRGGBB" format QML produces.
    Q_INVOKABLE void setColors(const QString &background, const QString &foreground,
                               const QString &accent);

signals:
    void documentChanged();

private:
    QPointer<QQuickTextDocument> m_quickDocument;
    MarkdownHighlighter *m_highlighter = nullptr;
    QString m_background;
    QString m_foreground;
    QString m_accent;
};
