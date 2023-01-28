

void Main() {
	init();
	while (true) {
		step();
		yield();
	}
}

void Render() {
	if (!showMapInfo) return;

	
}

void RenderMenu() {
	if(UI::MenuItem("\\$8f0" + Icons::Map + "\\$z Map Info", "", showMapInfo)) {
		showMapInfo = !showMapInfo;
	}
}

void OnSettingsChanged() {
    init();
}

void init() {

}

void step() {

}
