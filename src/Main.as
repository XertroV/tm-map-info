// int g_NvgFont = nvg::LoadFont("fonts/Montserrat-BoldItalic.ttf", true, true);
int g_NvgFont = nvg::LoadFont("fonts/Montserrat-SemiBoldItalic.ttf", true, true);
UI::Font@ g_ImguiFont = null;

void Main() {
    if (Meta::GetPluginFromID("BetterLoadingScreen") !is null && S_ShowLoadingScreenInfo) {
        // we only need to use imgui fonts if BLS is installed, as it renders atop the nvg layer. if
        // BLS isn't installed, we can use more-performant nvg rendering
        LoadImGUIFont();
    }
    startnew(ClearTaskCoro);
    startnew(TOTD::LoadTOTDs);
    startnew(MonitorUIVisible);
    startnew(CacheTodaysDate);
}

void LoadImGUIFont() {
    if (g_ImguiFont !is null) return;
    @g_ImguiFont = UI::LoadFont("fonts/Montserrat-SemiBoldItalic.ttf", 40.f);
}

string TodaysDate = "xxxx-xx-xx";
void CacheTodaysDate() {
    while (true) {
        TodaysDate = FmtTimestampDateOnly(-1, false);
        sleep(15000);
    }
}

bool _GameUIVisible = false;
void MonitorUIVisible() {
    while (true) {
        sleep(100);
        _GameUIVisible = UI::IsGameUIVisible();
    }
}

// load textures from within render loop when we need them.
void LoadTextures() {
    log_trace("Loading textures...");
    @tmDojoLogo = nvg::LoadTexture("img/tmdojo_logo.png");
    @tmIOLogo = nvg::LoadTexture("img/tmio_logo.png");
    @tmxLogo = nvg::LoadTexture("img/tmx_logo.png");
    log_trace("Loaded textures.");
}

/** Called every frame. `dt` is the delta time (milliseconds since last frame).
*/
void Update(float dt) {
    CheckForNewMap();
}

void Render() {
    if (g_MapInfo !is null) {
        // call once on first entering a map.
        if (tmDojoLogo is null)
            LoadTextures();
        g_MapInfo.Draw();
        if (S_ShowDebugUI) g_MapInfo.Draw_DebugUI();

        auto loadProgress = GetApp().LoadProgress;
        if (loadProgress !is null && loadProgress.State != NGameLoadProgress_SMgr::EState::Disabled) {
            g_MapInfo.Draw_LoadingScreen();
        }
    }
}

const string MenuLabel = "\\$8f0" + Icons::Map + "\\$z " + Meta::ExecutingPlugin().Name;

void RenderMenu() {
    if (UI::MenuItem(MenuLabel, "", S_ShowMapInfo)) {
        S_ShowMapInfo = !S_ShowMapInfo;
    }

    if (S_ShowDebugMenuItem && UI::MenuItem(MenuLabel + " (Debug Window)", "", S_ShowDebugUI)) {
        S_ShowDebugUI = !S_ShowDebugUI;
    }
}

void OnSettingsChanged() {
    if (S_ShowLoadingScreenInfo) @g_ImguiFont = UI::LoadFont("fonts/Montserrat-SemiBoldItalic.ttf", 40.f);
}

const string FmtTimestamp(int64 timestamp) {
    // return Time::FormatString("%c", timestamp);
    return Time::FormatString("%Y-%m-%d (%a) %H:%M", timestamp);
}

const string FmtTimestampUTC(int64 timestamp) {
    return Time::FormatStringUTC("%Y-%m-%d (%a) %H:%M", timestamp);
}

const string FmtTimestampDateOnly(int64 timestamp = -1, bool withDay = true) {
    return Time::FormatString(withDay ? "%Y-%m-%d (%a)" : "%Y-%m-%d", timestamp);
}

const string FmtTimestampDateOnlyUTC(int64 timestamp) {
    return Time::FormatStringUTC("%Y-%m-%d (%a)", timestamp);
}

bool IsWithin(vec2 pos, vec2 topLeft, vec2 size) {
    vec2 d1 = topLeft - pos;
    vec2 d2 = (topLeft + size) - pos;
    return (d1.x >= 0 && d1.y >= 0 && d2.x <= 0 && d2.y <= 0)
        || (d1.x <= 0 && d1.y <= 0 && d2.x >= 0 && d2.y >= 0)
        || (d1.x <= 0 && d1.y >= 0 && d2.x >= 0 && d2.y <= 0)
        || (d1.x >= 0 && d1.y <= 0 && d2.x <= 0 && d2.y >= 0)
        ;
}

vec2 g_MouseCoords;

/** Called whenever the mouse moves. `x` and `y` are the viewport coordinates.
*/
void OnMouseMove(int x, int y) {
    g_MouseCoords.x = x;
    g_MouseCoords.y = y;
    // trace('Updated mouse pos ' + Time::Now);
}

/** Called whenever a mouse button is pressed. `x` and `y` are the viewport coordinates.
*/
UI::InputBlocking OnMouseButton(bool down, int button, int x, int y) {
    OnMouseMove(x, y);
    if (g_MapInfo !is null) {
        if (g_MapInfo.OnMouseButton(down, button))
            return UI::InputBlocking::Block;
    }
    return UI::InputBlocking::DoNothing;
}


void DrawTexture(vec2 pos, vec2 size, nvg::Texture@ tex, float alpha = 1.0) {
    nvg::BeginPath();
    nvg::FillPaint(nvg::TexturePattern(pos, size, 0, tex, alpha));
    nvg::Rect(pos, size);
    nvg::Fill();
    nvg::ClosePath();
}
