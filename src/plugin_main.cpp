#include <obs-module.h>
#include <obs-frontend-api.h>

#include <QAction>
#include <QCoreApplication>
#include <QDockWidget>
#include <QEvent>
#include <QKeyEvent>
#include <QLabel>
#include <QLineEdit>
#include <QMainWindow>
#include <QMouseEvent>
#include <QPixmap>
#include <QSizePolicy>
#include <QTimer>
#include <QUrl>
#include <QVBoxLayout>
#include <QWebEngineView>
#include <QWheelEvent>
#include <QtGlobal>

OBS_DECLARE_MODULE()

#define PLUGIN_NAME "Hyprland Browser Wrapper"

namespace {

bool IsWaylandSession()
{
    if (qEnvironmentVariableIsSet("WAYLAND_DISPLAY") || qEnvironmentVariableIsSet("WAYLAND_SOCKET"))
        return true;

    const QString sessionType = qEnvironmentVariable("XDG_SESSION_TYPE");
    return sessionType.compare("wayland", Qt::CaseInsensitive) == 0;
}

bool IsHyprland()
{
    const QString desktop = qEnvironmentVariable("XDG_CURRENT_DESKTOP");
    return desktop.contains("Hyprland", Qt::CaseInsensitive);
}

QWidget *CreateBrowserContent(QWidget *parent)
{
    QWidget *container = new QWidget(parent);
    QVBoxLayout *layout = new QVBoxLayout(container);
    layout->setContentsMargins(0, 0, 0, 0);

    QLineEdit *urlInput = new QLineEdit(container);
    urlInput->setPlaceholderText("Enter URL here (e.g., https://google.com)");

    QWebEngineView *realBrowser = new QWebEngineView(container);
    realBrowser->setUrl(QUrl("https://obsproject.com"));

    QObject::connect(urlInput, &QLineEdit::returnPressed, [realBrowser, urlInput]() {
        QString input = urlInput->text();
        if (!input.startsWith("http://") && !input.startsWith("https://"))
            input = "https://" + input;
        realBrowser->load(QUrl(input));
    });

    layout->addWidget(urlInput);
    layout->addWidget(realBrowser);
    layout->setStretchFactor(realBrowser, 1);

    return container;
}

class HyprBrowserWindow : public QWidget {
public:
    explicit HyprBrowserWindow(QWidget *parent = nullptr) : QWidget(parent)
    {
        setWindowTitle("Hyprland Browser Wrapper");
        setObjectName("HyprBrowserWindow");
        setAttribute(Qt::WA_DeleteOnClose, true);
        setWindowFlags(Qt::Tool | Qt::CustomizeWindowHint | Qt::WindowStaysOnTopHint);

        QVBoxLayout *layout = new QVBoxLayout(this);
        layout->setContentsMargins(0, 0, 0, 0);
        layout->addWidget(CreateBrowserContent(this));
    }
};

class HyprBrowserDock : public QDockWidget {
public:
    explicit HyprBrowserDock(QWidget *parent = nullptr) : QDockWidget(parent)
    {
        setWindowTitle("Hyprland Browser Wrapper");
        setObjectName("HyprBrowserDock");
        setFeatures(QDockWidget::DockWidgetMovable | QDockWidget::DockWidgetClosable |
                    QDockWidget::DockWidgetFloatable);
        setAllowedAreas(Qt::LeftDockWidgetArea | Qt::RightDockWidgetArea | Qt::TopDockWidgetArea |
                        Qt::BottomDockWidgetArea);
        setWidget(CreateBrowserContent(this));
    }
};

class HyprBrowserTextureWidget : public QWidget {
    Q_OBJECT
public:
    explicit HyprBrowserTextureWidget(QWidget *parent = nullptr) : QWidget(parent)
    {
        setContentsMargins(0, 0, 0, 0);

        QVBoxLayout *layout = new QVBoxLayout(this);
        layout->setContentsMargins(0, 0, 0, 0);

        urlInput = new QLineEdit(this);
        urlInput->setPlaceholderText("Enter URL here (e.g., https://google.com)");

        browser = new QWebEngineView(this);
        browser->setAttribute(Qt::WA_DontShowOnScreen, true);
        browser->resize(1280, 720);
        browser->setUrl(QUrl("https://obsproject.com"));
        browser->show();
        browser->hide();

        preview = new QLabel("Rendering (Wayland-safe dock)...", this);
        preview->setAlignment(Qt::AlignCenter);
        preview->setMinimumSize(320, 180);
        preview->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
        preview->setFocusPolicy(Qt::StrongFocus);
        preview->installEventFilter(this);

        QObject::connect(urlInput, &QLineEdit::returnPressed, [this]() {
            QString input = urlInput->text();
            if (!input.startsWith("http://") && !input.startsWith("https://"))
                input = "https://" + input;
            browser->load(QUrl(input));
        });

        layout->addWidget(urlInput);
        layout->addWidget(preview);
        layout->setStretchFactor(preview, 1);

        frameTimer = new QTimer(this);
        frameTimer->setInterval(150);
        QObject::connect(frameTimer, &QTimer::timeout, this, &HyprBrowserTextureWidget::UpdateFrame);
        frameTimer->start();
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
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
                             ke->nativeVirtualKey(), ke->nativeModifiers(), ke->text(),
                             ke->isAutoRepeat(), ke->count());
            QCoreApplication::sendEvent(browser, &mapped);
            return true;
        }
        default:
            break;
        }

        return QWidget::eventFilter(watched, event);
    }

private slots:
    void UpdateFrame()
    {
        QPixmap pixmap = browser->grab();
        if (pixmap.isNull())
            return;

        QSize target = preview->size().isEmpty() ? QSize(320, 180) : preview->size();
        preview->setPixmap(pixmap.scaled(target, Qt::KeepAspectRatio, Qt::SmoothTransformation));
    }

private:
    QPointF MapToBrowser(const QPointF &labelPos) const
    {
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
    explicit HyprBrowserTextureDock(QWidget *parent = nullptr) : QDockWidget(parent)
    {
        setWindowTitle("Hyprland Browser Wrapper (Wayland dock workaround)");
        setObjectName("HyprBrowserTextureDock");
        setFeatures(QDockWidget::DockWidgetMovable | QDockWidget::DockWidgetClosable |
                    QDockWidget::DockWidgetFloatable);
        setAllowedAreas(Qt::LeftDockWidgetArea | Qt::RightDockWidgetArea | Qt::TopDockWidgetArea |
                        Qt::BottomDockWidgetArea);
        setWidget(new HyprBrowserTextureWidget(this));
    }
};

void AttachAndShowDock(QMainWindow *mainWindow, QDockWidget *dock, Qt::DockWidgetArea area, bool floating)
{
    mainWindow->addDockWidget(area, dock);
    dock->setFloating(floating);
    dock->show();
    dock->raise();
    dock->activateWindow();
}

void CreateHyprWindow(void *)
{
    auto *window = new HyprBrowserWindow();
    window->show();
    window->raise();
    window->activateWindow();
}

void CreateHyprDock(void *)
{
    QMainWindow *mainWindow = static_cast<QMainWindow *>(obs_frontend_get_main_window());
    if (!mainWindow)
        return;

    if (IsWaylandSession()) {
        blog(LOG_WARNING,
             "[hyprland-browser-wrapper] Wayland session detected (Hyprland=%d); "
             "using texture-based dock to avoid QWebEngine reparent crash.",
             IsHyprland());

        auto *dock = new HyprBrowserTextureDock(mainWindow);
        AttachAndShowDock(mainWindow, dock, Qt::RightDockWidgetArea, false);
        return;
    }

    auto *dock = new HyprBrowserDock(mainWindow);
    AttachAndShowDock(mainWindow, dock, Qt::RightDockWidgetArea, true);
}

void CreateHyprTextureDock(void *)
{
    QMainWindow *mainWindow = static_cast<QMainWindow *>(obs_frontend_get_main_window());
    if (!mainWindow)
        return;

    auto *dock = new HyprBrowserTextureDock(mainWindow);
    AttachAndShowDock(mainWindow, dock, Qt::RightDockWidgetArea, false);
}

} // namespace

bool obs_module_load(void)
{
    QAction *windowAction = static_cast<QAction *>(
        obs_frontend_add_tools_menu_qaction("Hypr Browser (Wayland-safe window)"));
    QObject::connect(windowAction, &QAction::triggered, [](bool) { CreateHyprWindow(nullptr); });

    QAction *dockAction = static_cast<QAction *>(obs_frontend_add_tools_menu_qaction(
        "Hypr Browser (Dock; auto Wayland workaround)"));
    QObject::connect(dockAction, &QAction::triggered, [](bool) { CreateHyprDock(nullptr); });

    QAction *textureAction = static_cast<QAction *>(obs_frontend_add_tools_menu_qaction(
        "Hypr Browser (Force texture dock)"));
    QObject::connect(textureAction, &QAction::triggered, [](bool) { CreateHyprTextureDock(nullptr); });

    return true;
}

void obs_module_unload(void) {}

const char *obs_module_author(void)
{
    return "Hyprland User";
}

const char *obs_module_name(void)
{
    return PLUGIN_NAME;
}

const char *obs_module_description(void)
{
    return "A wrapper to force browser docks to render correctly on Hyprland/Wayland";
}

#include "plugin_main.moc"
