#include "plugin.h"

#include "markdownhighlighter.h"

#include <QtQml>

void MarkdownHighlightPlugin::registerTypes(const char* uri) {
  Q_ASSERT(QLatin1String(uri) == QLatin1String("MarkdownHighlight"));
  qmlRegisterType<MarkdownHighlighter>(uri, 1, 0, "MarkdownHighlighter");
}
