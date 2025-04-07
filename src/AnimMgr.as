class AnimMgr {
    float t = 0.0;
    float animOut = 0.0;
    float animDuration = 250.0;
    bool lastGrowing = false;
    uint lastGrowingChange = 0;
    uint lastGrowingCheck = 0;

    AnimMgr(bool startOpen = false, float duration = 250.0) {
        t = startOpen ? 1.0 : 0.0;
        animDuration = duration;
    }

    void SetAt(float newT) {
        t = newT;
        lastGrowingChange = Time::Now;
    }

    // return true if open (animOut > 0)
    bool Update(bool growing, float clampMax = 1.0) {
        if (lastGrowingChange == 0) lastGrowingChange = Time::Now;
        if (lastGrowingCheck == 0) lastGrowingCheck = Time::Now;

        float delta = float(int(Time::Now) - int(lastGrowingCheck)) / animDuration;
        delta = Math::Min(delta, 0.2);
        lastGrowingCheck = Time::Now;

        float sign = growing ? 1.0 : -1.0;
        t = Math::Clamp(t + sign * delta, 0.0, 1.0);
        if (lastGrowing != growing) {
            lastGrowing = growing;
            lastGrowingChange = Time::Now;
        }

        // QuadOut easing
        animOut = -(t * (t - 2.));
        animOut = Math::Min(clampMax, animOut);
        return animOut > 0.;
    }

    float Progress {
        get {
            return animOut;
        }
    }

    bool IsDone {
        get {
            return animOut >= 1.0;
        }
    }
}
