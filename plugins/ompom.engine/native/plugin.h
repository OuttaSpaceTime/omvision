#pragma once
#include <QQmlEngineExtensionPlugin>

// Anchor class for automatic QML_ELEMENT registration (NoteHighlighter).
// Plain qmake's "CONFIG += plugin qmltypes" doesn't synthesize this on its
// own -- without a Q_PLUGIN_METADATA-carrying QQmlEngineExtensionPlugin
// subclass somewhere in the target, the module's qmldir resolves but the
// generated registration function never actually runs, so 'import
// Ompom.Highlight 1.0' does nothing.
class OmpomHighlightPlugin : public QQmlEngineExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlEngineExtensionInterface_iid)
};
