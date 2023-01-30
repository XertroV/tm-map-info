namespace TmDojo {
    string mapInfoEndpoint = "https://api.tmdojo.com/maps/{uid}/info";

    Json::Value@ GetMapInfo(const string &in uid) {
        string url = mapInfoEndpoint.Replace("{uid}", uid);
        auto req = PluginGetRequest(url);
        req.Start();
        while (!req.Finished()) yield();
        if (req.ResponseCode() >= 400 || req.ResponseCode() < 200 || req.Error().Length > 0) {
            warn("[status:" + req.ResponseCode() + "] Error getting map by UID from TM Dojo: " + req.Error());
            return null;
        }
        print("Debug tmdojo get map by uid: " + req.String());
        return Json::Parse(req.String());
    }

}
