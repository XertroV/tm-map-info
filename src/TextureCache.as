namespace TextureCache {
    dictionary textures;

    MapThumbnailTexture@ Get(const string &in url) {
        if (!textures.Exists(url)) {
            textures[url] = @MapThumbnailTexture(url);
        }
        auto @ret = cast<MapThumbnailTexture>(textures[url]);
        ret.lastAccessed = Time::Now;
        return ret;
    }
}

// Cache a texture
// -- alternate design idea: don't cache the textures, but cache the buffer. Then null the textures on map change, and reload dynamically when used again. Avoids memory leak with texture files, but also avoids redownloading.
class MapThumbnailTexture {
    nvg::Texture@ nvgTex = null;
    UI::Texture@ uiTex = null;
    string url;
    bool encounteredError = false;
    uint lastAccessed = Time::Now;

    MapThumbnailTexture(const string &in url) {
        this.url = url;
        startnew(CoroutineFunc(this.GetLoadTextures));
    }

    bool IsLoaded() {
        return nvgTex !is null && uiTex !is null;
    }

    void GetLoadTextures() {
        encounteredError = false;
        log_trace('Downloading thumbnail: ' + url);
        auto req = Net::HttpGet(url);
        while (!req.Finished()) yield();
        if (req.ResponseCode() != 200) {
            log_warn('GET Thumbnail response: ' + req.ResponseCode());
            encounteredError = true;
            return;
        }
        auto buf = req.Buffer();
        @nvgTex = nvg::LoadTexture(buf);
        buf.Seek(0);
        @uiTex = UI::LoadTexture(buf);
    }
}
