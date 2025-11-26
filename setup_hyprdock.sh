#!/bin/bash
set -euo pipefail

# Define project name
PROJECT_NAME="hyprland-browser-wrapper"

# If we're already inside the project folder, avoid nesting another copy
if [[ "$(basename "$PWD")" != "$PROJECT_NAME" ]]; then
  echo "Creating project structure for $PROJECT_NAME..."
  mkdir -p "$PROJECT_NAME"
  cd "$PROJECT_NAME" || exit 1
else
  echo "Using existing directory $PWD"
fi

# Create source directory
mkdir -p src

# 1. Generate CMakeLists.txt
echo "Generating CMakeLists.txt..."
cat << 'EOF' > CMakeLists.txt
cmake_minimum_required(VERSION 3.16)
project(hyprland-browser-wrapper VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

include(GNUInstallDirs)

# Find OBS and Qt6 packages
# WebEngineWidgets is required for the browser view
find_package(libobs REQUIRED)
find_package(Qt6 COMPONENTS Widgets Core Gui WebEngineWidgets REQUIRED)

# Define the plugin library
add_library(hyprland-browser-wrapper MODULE
    src/plugin_main.cpp
)

# Make sure obs headers are visible (libobs installs to /usr/include/obs on many distros)
target_include_directories(hyprland-browser-wrapper PRIVATE
    ${LIBOBS_INCLUDE_DIR}
    /usr/include/obs
)

# Link necessary libraries
target_link_libraries(hyprland-browser-wrapper
    PRIVATE
    obs
    Qt6::Core
    Qt6::Widgets
    Qt6::Gui
    Qt6::WebEngineWidgets
)

# Installation paths
if(NOT DEFINED OBS_PLUGIN_DESTINATION)
    set(OBS_PLUGIN_DESTINATION "${CMAKE_INSTALL_LIBDIR}/obs-plugins")
endif()

if(NOT DEFINED OBS_DATA_DESTINATION)
    set(OBS_DATA_DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/obs/obs-plugins/hyprland-browser-wrapper")
endif()

install(TARGETS hyprland-browser-wrapper DESTINATION "${OBS_PLUGIN_DESTINATION}")
EOF

# 2. Generate src/plugin_main.cpp
echo "Generating src/plugin_main.cpp..."
cat << 'EOF' > src/plugin_main.cpp
#include <obs-module.h>
#include <obs-frontend-api.h>
#include <QUrl>
#include <QDockWidget>
#include <QMainWindow>
#include <QAction>
#include <QVBoxLayout>
#include <QLineEdit>
#include <QWidget>
#include <QWebEngineView>
#include <QLabel>
#include <QTimer>
#include <QEvent>
#include <QMouseEvent>
#include <QWheelEvent>
#include <QKeyEvent>
#include <QCoreApplication>

OBS_DECLARE_MODULE()

#define PLUGIN_NAME "Hyprland Browser Wrapper"

// Shared browser content builder
static QWidget *CreateBrowserContent(QWidget *parent) {
    QWidget *container = new QWidget(parent);
    QVBoxLayout *layout = new QVBoxLayout(container);

    // Input for the URL
    QLineEdit *urlInput = new QLineEdit(container);
    urlInput->setPlaceholderText("Enter URL here (e.g., https://google.com)");

    // The real browser engine implementation
    QWebEngineView *realBrowser = new QWebEngineView(container);

    // Set a default page so it isn't blank on launch
    realBrowser->setUrl(QUrl("https://obsproject.com"));

    // Connect the input field to the browser's load function
    QObject::connect(urlInput, &QLineEdit::returnPressed, [realBrowser, urlInput]() {
        QString input = urlInput->text();
        // Simple check to append http if missing, for convenience
        if (!input.startsWith("http://") && !input.startsWith("https://")) {
            input = "https://" + input;
        }
        realBrowser->load(QUrl(input));
    });

    layout->addWidget(urlInput);
    layout->addWidget(realBrowser);

    // Ensure the browser takes up all available space
    layout->setStretchFactor(realBrowser, 1);

    return container;
}

// Standalone floating window (Wayland-safe)
class HyprBrowserWindow : public QWidget {
public:
    HyprBrowserWindow(QWidget *parent = nullptr) : QWidget(parent) {
        setWindowTitle("Hyprland Browser Wrapper");
        setObjectName("HyprBrowserWindow");
        setAttribute(Qt::WA_DeleteOnClose, true);

        // Critical flags for Hyprland/Wayland visibility; keep as a tool window so it floats
        setWindowFlags(Qt::Tool | Qt::CustomizeWindowHint | Qt::WindowStaysOnTopHint);
        setContentsMargins(0, 0, 0, 0);

        QVBoxLayout *layout = new QVBoxLayout(this);
        layout->setContentsMargins(0, 0, 0, 0);
        layout->addWidget(CreateBrowserContent(this));
    }
};

// Dockable variant (best effort on X11; known to be fragile on Wayland)
class HyprBrowserDock : public QDockWidget {
public:
    HyprBrowserDock(QWidget *parent = nullptr) : QDockWidget(parent) {
        setWindowTitle("Hyprland Browser Wrapper");
        setObjectName("HyprBrowserDock");
        // Original behavior: force a window surface and top-most
        setWindowFlags(Qt::Window | Qt::CustomizeWindowHint | Qt::WindowStaysOnTopHint);
        setFeatures(QDockWidget::DockWidgetMovable | QDockWidget::DockWidgetClosable | QDockWidget::DockWidgetFloatable);
        setAllowedAreas(Qt::LeftDockWidgetArea | Qt::RightDockWidgetArea | Qt::TopDockWidgetArea | Qt::BottomDockWidgetArea);
        setWidget(CreateBrowserContent(this));
    }
};

// Texture-grab variant (super experimental): hides the WebEngine view offscreen and
// blits grabbed frames into a QLabel to avoid reparenting a live surface.
class HyprBrowserTextureWidget : public QWidget {
    Q_OBJECT
public:
    explicit HyprBrowserTextureWidget(QWidget *parent = nullptr) : QWidget(parent) {
        setContentsMargins(0, 0, 0, 0);

        QVBoxLayout *layout = new QVBoxLayout(this);
        layout->setContentsMargins(0, 0, 0, 0);

        urlInput = new QLineEdit(this);
        urlInput->setPlaceholderText("Enter URL here (e.g., https://google.com)");

        browser = new QWebEngineView(this);
        browser->setAttribute(Qt::WA_DontShowOnScreen, true);
        browser->resize(1280, 720);
        browser->setUrl(QUrl("https://obsproject.com"));
        browser->show();   // ensure it renders
        browser->hide();   // but keep it offscreen

        preview = new QLabel("Rendering (super experimental)...", this);
        preview->setAlignment(Qt::AlignCenter);
        preview->setMinimumSize(320, 180);
        preview->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
        preview->setFocusPolicy(Qt::StrongFocus);
        preview->installEventFilter(this);

        QObject::connect(urlInput, &QLineEdit::returnPressed, [this]() {
            QString input = urlInput->text();
            if (!input.startsWith("http://") && !input.startsWith("https://")) {
                input = "https://" + input;
            }
            browser->load(QUrl(input));
        });

        layout->addWidget(urlInput);
        layout->addWidget(preview);
        layout->setStretchFactor(preview, 1);

        frameTimer = new QTimer(this);
        frameTimer->setInterval(150); // ~6-7 fps to keep CPU/GPU reasonable
        QObject::connect(frameTimer, &QTimer::timeout, this, &HyprBrowserTextureWidget::UpdateFrame);
        frameTimer->start();
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override {
        if (watched != preview)
            return QWidget::eventFilter(watched, event);

        switch (event->type()) {
        case QEvent::MouseButtonPress:
        case QEvent::MouseButtonRelease:
        case QEvent::MouseMove: {
            auto *me = static_cast<QMouseEvent *>(event);
            QPointF pos = MapToBrowser(me->position());
            QMouseEvent mapped(me->type(), pos, me->button(), me->buttons(), me->modifiers());
            QCoreApplication::sendEvent(browser, &mapped);
            preview->setFocus();
            return true;
        }
        case QEvent::Wheel: {
            auto *we = static_cast<QWheelEvent *>(event);
            QPointF pos = MapToBrowser(we->position());
            QWheelEvent mapped(pos, we->globalPosition(), we->pixelDelta(), we->angleDelta(),
                               we->buttons(), we->modifiers(), we->phase(), we->inverted(),
                               we->source());
            QCoreApplication::sendEvent(browser, &mapped);
            return true;
        }
        case QEvent::KeyPress:
        case QEvent::KeyRelease: {
            auto *ke = static_cast<QKeyEvent *>(event);
            QKeyEvent mapped(ke->type(), ke->key(), ke->modifiers(), ke->nativeScanCode(),
                             ke->nativeVirtualKey(), ke->nativeModifiers(), ke->text(), ke->isAutoRepeat(),
                             ke->count());
            QCoreApplication::sendEvent(browser, &mapped);
            return true;
        }
        default:
            break;
        }

        return QWidget::eventFilter(watched, event);
    }

private slots:
    void UpdateFrame() {
        QPixmap pixmap = browser->grab();
        if (pixmap.isNull())
            return;
        QSize target = preview->size().isEmpty() ? QSize(320, 180) : preview->size();
        preview->setPixmap(pixmap.scaled(target, Qt::KeepAspectRatio, Qt::SmoothTransformation));
    }

private:
    QPointF MapToBrowser(const QPointF &labelPos) const {
        QSizeF src = preview->size();
        QSizeF dst = browser->size();
        if (src.isEmpty())
            return labelPos;
        qreal scaleX = dst.width() / src.width();
        qreal scaleY = dst.height() / src.height();
        return QPointF(labelPos.x() * scaleX, labelPos.y() * scaleY);
    }

    QLineEdit *urlInput = nullptr;
    QWebEngineView *browser = nullptr;
    QLabel *preview = nullptr;
    QTimer *frameTimer = nullptr;
};

class HyprBrowserTextureDock : public QDockWidget {
public:
    explicit HyprBrowserTextureDock(QWidget *parent = nullptr) : QDockWidget(parent) {
        setWindowTitle("Hyprland Browser Wrapper (Texture Embed)");
        setObjectName("HyprBrowserTextureDock");
        setFeatures(QDockWidget::DockWidgetMovable | QDockWidget::DockWidgetClosable | QDockWidget::DockWidgetFloatable);
        setAllowedAreas(Qt::LeftDockWidgetArea | Qt::RightDockWidgetArea | Qt::TopDockWidgetArea | Qt::BottomDockWidgetArea);
        setWidget(new HyprBrowserTextureWidget(this));
    }
};

static void CreateHyprWindow(void *data) {
    Q_UNUSED(data);

    HyprBrowserWindow *window = new HyprBrowserWindow();
    window->show();
    window->raise();
    window->activateWindow();
}

static void CreateHyprDock(void *data) {
    Q_UNUSED(data);

    QMainWindow *mainWindow = (QMainWindow *)obs_frontend_get_main_window();
    if (!mainWindow) return;

    HyprBrowserDock *dock = new HyprBrowserDock(mainWindow);
    mainWindow->addDockWidget(Qt::RightDockWidgetArea, dock);
    dock->setFloating(true);
    dock->show();
    dock->raise();
    dock->activateWindow();
}

static void CreateHyprTextureDock(void *data) {
    Q_UNUSED(data);

    QMainWindow *mainWindow = (QMainWindow *)obs_frontend_get_main_window();
    if (!mainWindow) return;

    HyprBrowserTextureDock *dock = new HyprBrowserTextureDock(mainWindow);
    mainWindow->addDockWidget(Qt::RightDockWidgetArea, dock);
    dock->setFloating(false);
    dock->show();
    dock->raise();
    dock->activateWindow();
}

bool obs_module_load(void) {
    QAction *windowAction = (QAction *)obs_frontend_add_tools_menu_qaction("Hypr Browser (Wayland-safe)");
    QObject::connect(windowAction, &QAction::triggered, [](bool) { CreateHyprWindow(nullptr); });

    QAction *dockAction = (QAction *)obs_frontend_add_tools_menu_qaction("Hypr Browser (Unsafe dock, experimental)");
    QObject::connect(dockAction, &QAction::triggered, [](bool) { CreateHyprDock(nullptr); });

    QAction *textureAction = (QAction *)obs_frontend_add_tools_menu_qaction("Hypr Browser (Texture embed, super experimental)");
    QObject::connect(textureAction, &QAction::triggered, [](bool) { CreateHyprTextureDock(nullptr); });

    return true;
}

void obs_module_unload(void) {}

const char *obs_module_author(void) {
    return "Hyprland User";
}

const char *obs_module_name(void) {
    return PLUGIN_NAME;
}

const char *obs_module_description(void) {
    return "A wrapper to force browser docks to render correctly on Hyprland/Wayland";
}

#include "plugin_main.moc"
EOF

echo "Setup complete!"
echo "To build the plugin, run:"
echo "  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release"
echo "  cmake --build build -j\$(nproc)"
