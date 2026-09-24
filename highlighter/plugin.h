#pragma once

// Registers MarkdownHighlighter into the `MarkdownHighlight` QML module.
//
// QQmlExtensionPlugin (rather than QQmlEngineExtensionPlugin) on purpose: it
// registers types from plain C++ with qmlRegisterType, so the module needs no
// qmltyperegistrar step and the whole thing builds with moc + g++ alone. That
// keeps this repo free of a cmake/ninja dependency -- one shell script builds
// it, which is as close to the project's "no build step" property as a C++
// highlighter can get.

#include <QQmlExtensionPlugin>

class MarkdownHighlightPlugin : public QQmlExtensionPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlExtensionInterface/1.0")

public:
  void registerTypes(const char* uri) override;
};
