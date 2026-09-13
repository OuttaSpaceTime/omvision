TEMPLATE = lib
CONFIG += plugin qmltypes
QT += qml gui quick

TARGET = ompomhighlight
QML_IMPORT_NAME = Ompom.Highlight
QML_IMPORT_MAJOR_VERSION = 1

DESTDIR = Ompom/Highlight
QMLTYPES_FILENAME = Ompom/Highlight/plugins.qmltypes

SOURCES += markdownhighlighter.cpp notehighlighter.cpp plugin.cpp
HEADERS += markdownhighlighter.h notehighlighter.h plugin.h
