int g_NvgFont = nvg::LoadFont("fonts/Montserrat-SemiBoldItalic.ttf", true, true);

void Main() {
    startnew(ClearTaskCoro);
	startnew(TOTD::LoadTOTDs);
	while (true) {
		step();
		yield();
	}
}

void Render() {
    DrawMapInfoUI();
	if (g_MapInfo !is null) {
		g_MapInfo.Draw();
		g_MapInfo.Draw_DebugUI();
	}
}

const string MenuLabel = "\\$8f0" + Icons::Map + "\\$z " + Meta::ExecutingPlugin().Name;

void RenderMenu() {
	if(UI::MenuItem(MenuLabel, "", S_ShowMapInfo)) {
		S_ShowMapInfo = !S_ShowMapInfo;
	}
}

void OnSettingsChanged() {
	// no reason to call this again, yet
    // init();
}

const string FmtTimestamp(uint64 timestamp) {
	// return Time::FormatString("%c", timestamp);
	return Time::FormatString("%Y-%m-%d (%a) %H:%M", timestamp);
}

const string FmtTimestampUTC(uint64 timestamp) {
	return Time::FormatStringUTC("%Y-%m-%d (%a) %H:%M", timestamp);
}

const string FmtTimestampDateOnlyUTC(uint64 timestamp) {
	return Time::FormatStringUTC("%Y-%m-%d (%a)", timestamp);
}
