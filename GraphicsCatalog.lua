local _, NS = ...
local tr = NS.Text

-- Console settings the addon may touch, nothing else. The client decides which exist:
-- rows without a matching console variable stay hidden, so the list cannot go stale.
-- cost: 0 none, 1 low, 2 medium, 3 high (rough FPS impact, not a measurement).
-- `restart`: the client only shows the new value after a game restart.
local function range(name, de, en, minimum, maximum, step, cost, dd, de2, restart)
    return {name = name, title = tr(de, en), kind = "range", minimum = minimum, maximum = maximum, step = step, cost = cost, hint = tr(dd, de2), restart = restart}
end
local function toggle(name, de, en, cost, dd, de2, restart)
    return {name = name, title = tr(de, en), kind = "toggle", minimum = 0, maximum = 1, step = 1, cost = cost, hint = tr(dd, de2), restart = restart}
end
local function group(key, de, en, rows)
    return {key = key, title = tr(de, en), rows = rows}
end

NS.GraphicsCatalog = {
    group("distance", "Sichtweite und Aufploppen", "View distance and pop-in", {
        -- Game menu sliders. Writing one makes the client reset its detail values, so they are always
        -- written before everything else (see Graphics.lua).
        range("graphicsViewDistance", "Sichtweite (Spielmenü-Stufe)", "View distance (game menu level)", 0, 9, 1, 3,
            "Stufe 0 bis 9, entspricht 1 bis 10 im Spielmenü.", "Level 0 to 9, the game menu shows 1 to 10."),
        range("graphicsEnvironmentDetail", "Umgebungsdetails (Spielmenü-Stufe)", "Environment detail (game menu level)", 0, 9, 1, 2,
            "Mehr Bäume, Felsen und Dekoration in der Ferne. Stufe 0 bis 9.", "More trees, rocks and props in the distance. Level 0 to 9."),
        range("horizonStart", "Beginn des Horizonts", "Horizon start", 500, 5000, 100, 2,
            "Ab hier beginnt die vereinfachte Fernsicht.", "Where the simplified far view begins."),
        range("lodObjectFadeScale", "Objekte ausblenden ab", "Object fade distance", 25, 300, 5, 2,
            "Höhere Werte blenden Objekte später aus.", "Higher values fade objects out later."),
        range("lodObjectCullSize", "Kleinste sichtbare Objekte", "Smallest visible objects", 1, 40, 1, 2,
            "Niedrigere Werte zeichnen auch kleine Objekte in der Ferne.", "Lower values also draw small objects far away."),
        range("doodadLodScale", "Detailstufe von Dekoration", "Decoration detail", 25, 300, 5, 2,
            "Höhere Werte halten Kisten, Zäune und Felsen länger detailreich.", "Higher values keep crates, fences and rocks detailed for longer."),
        range("terrainLodDist", "Detailstufe des Geländes", "Terrain detail distance", 100, 1500, 50, 3,
            "", ""),
        range("entityLodDist", "Detailstufe von Figuren", "Character detail distance", 1, 20, 1, 2,
            "", ""),
    }),
    group("ground", "Gras und Bodendetails", "Grass and ground clutter", {
        range("groundEffectDensity", "Grasdichte", "Grass density", 16, 256, 8, 3,
            "", ""),
        range("groundEffectDist", "Grasweite", "Grass distance", 70, 500, 10, 3,
            "", ""),
        range("groundEffectFade", "Gras ausblenden ab", "Grass fade distance", 0, 500, 10, 2,
            "Beginn der weichen Ausblendung. Sollte unter der Grasweite liegen.", "Where the soft fade starts. Should stay below the grass distance."),
    }),
    group("lighting", "Licht und Atmosphäre", "Lighting and atmosphere", {
        range("graphicsLightMode", "Sekundäre Beleuchtung", "Secondary lighting", 0, 3, 1, 3,
            "0 Ausreichend, 1 Gut, 2 Hoch, 3 Ultra. Ultra kostet auf Forever besonders viele FPS.", "0 Fair, 1 Good, 2 High, 3 Ultra. Ultra costs a lot of FPS on Forever."),
        range("graphicsComputeEffects", "Compute-Effekte", "Compute effects", 0, 4, 1, 3,
            "Steuert unter anderem die Qualität des Nebels.", "Controls the fog quality among other things."),
        toggle("volumeFog", "Volumetrischer Nebel", "Volumetric fog", 2,
            "Dunst in Tälern und Wäldern. Aus ergibt klare Fernsicht.", "Haze in valleys and forests. Off gives clear far views."),
        range("graphicsSSAO", "Umgebungsverdeckung (SSAO)", "Ambient occlusion (SSAO)", 0, 4, 1, 2,
            "Kontaktschatten in Ecken und unter Objekten. 0 ist aus.", "Contact shadows in corners and under objects. 0 is off."),
        range("sunShafts", "Sonnenstrahlen", "Sun shafts", 0, 2, 1, 2,
            "Sichtbare Lichtstrahlen durch Bäume und Wolken. 0 aus, 1 niedrig, 2 hoch.", "Visible light rays through trees and clouds. 0 off, 1 low, 2 high."),
    }),
    group("shadows", "Schatten", "Shadows", {
        range("graphicsShadowQuality", "Schattenqualität (Spielmenü-Stufe)", "Shadow quality (game menu level)", 0, 5, 1, 3,
            "0 Niedrig bis 5 Ultra hoch, wie im Spielmenü.", "0 Low to 5 Ultra high, as in the game menu."),
        range("shadowNumCascades", "Schattenstufen", "Shadow cascades", 1, 4, 1, 3,
            "Mehr Stufen ergeben scharfe Schatten auch in der Ferne.", "More cascades keep shadows sharp in the distance."),
        toggle("shadowBlendCascades", "Schattenstufen überblenden", "Blend shadow cascades", 1,
            "Versteckt die Kante zwischen zwei Schattenstufen.", "Hides the seam between two shadow cascades."),
        toggle("shadowSoft", "Weiche Schatten", "Soft shadows", 2,
            "", ""),
    }),
    group("image", "Bildschärfe und Texturen", "Image sharpness and textures", {
        range("textureFilteringMode", "Texturfilterung", "Texture filtering", 0, 5, 1, 1,
            "0 bilinear, 1 trilinear, 2 bis 5 anisotrop 2×, 4×, 8×, 16×.", "0 bilinear, 1 trilinear, 2 to 5 anisotropic 2×, 4×, 8×, 16×."),
        range("terrainMipLevel", "Bodentexturen", "Ground textures", 0, 1, 1, 0,
            "0 ist die schärfste Stufe.", "0 is the sharpest level."),
        range("RenderScale", "Render-Skalierung", "Render scale", .5, 2, .01, 3,
            "Interne Auflösung im Verhältnis zur Bildschirmauflösung: 1 entspricht 100 %. Unter 1 wird hochskaliert, über 1 kostet viele FPS.",
            "Internal resolution relative to the screen resolution: 1 means 100%. Below 1 the image is upscaled, above 1 costs a lot of FPS."),
        range("ResampleQuality", "Skalierungsfilter", "Resample filter", 0, 3, 1, 1,
            "0 Punkt, 1 bilinear, 2 bikubisch, 3 FidelityFX Super Resolution. Wirkt nur, wenn die Render-Skalierung nicht 100 % beträgt.",
            "0 point, 1 bilinear, 2 bicubic, 3 FidelityFX Super Resolution. Only matters when the render scale is not 100%."),
        toggle("ResampleAlwaysSharpen", "Immer nachschärfen", "Always sharpen", 0,
            "Schärft das Bild auch bei voller Renderauflösung.", "Sharpens the image even at full render resolution."),
        range("ResampleSharpness", "Stärke der Schärfung", "Sharpening strength", 0, 2, .05, 0,
            "Kleinere Werte schärfen stärker: 0 ist am schärfsten, 2 am schwächsten.",
            "Lower values sharpen more: 0 is the sharpest, 2 the weakest."),
    }),
    group("water", "Wasser und Wetter", "Water and weather", {
        range("reflectionMode", "Spiegelungen im Wasser", "Water reflections", 0, 3, 1, 2,
            "0 ist aus, 3 spiegelt am meisten.", "0 is off, 3 reflects the most."),
        range("rippleDetail", "Wellen im Wasser", "Water ripples", 0, 2, 1, 1,
            "Wellen um Figuren und Objekte.", "Ripples around characters and objects."),
        range("weatherDensity", "Wetterdichte", "Weather density", 0, 3, 1, 1,
            "Menge von Regen, Schnee und Sand.", "Amount of rain, snow and sand."),
    }),
    group("effects", "Partikel und Effekte", "Particles and effects", {
        range("particleDensity", "Partikeldichte", "Particle density", 10, 100, 5, 2,
            "Menge der Partikel bei Zaubern und Umgebung.", "Amount of particles for spells and scenery."),
        toggle("projectedTextures", "Projizierte Texturen", "Projected textures", 1,
            "Zeichnet Effekte auf dem Boden wie Zauberkreise.", "Draws ground effects such as spell circles."),
        toggle("ffxDeath", "Graue Welt im Tod", "Grey world when dead", 0,
            "", ""),
    }),
    group("hdr", "HDR", "HDR", {
        toggle("HDROutput", "HDR-Ausgabe", "HDR output", 0,
            "Nur mit HDR-Monitor sinnvoll. Kann einen Neustart des Spiels brauchen.", "Only useful with an HDR monitor. May need a game restart.", true),
        range("HDRFactor", "HDR-Helligkeit", "HDR brightness", .5, 2, .1, 0,
            "Wirkt nur bei eingeschalteter HDR-Ausgabe.", "Only has an effect with HDR output on."),
    }),
    group("camera", "Kamera", "Camera", {
        range("cameraDistanceMaxZoomFactor", "Maximaler Kamera-Zoom", "Maximum camera zoom", 1, 2.6, .1, 0,
            "Das Spielmenü erlaubt bis 2,0.", "The game menu allows up to 2.0."),
    }),
    group("interface", "Spielgefühl", "Game feel", {
        range("SpellQueueWindow", "Zauber-Warteschlange (ms)", "Spell queue window (ms)", 0, 400, 10, 0,
            "Wie früh der nächste Zauber vorgemerkt wird.", "How early the next spell gets queued."),
        range("nameplateMaxDistance", "Reichweite der Namensplaketten", "Nameplate range", 20, 60, 1, 1,
            "", ""),
        range("screenshotQuality", "Screenshot-Qualität", "Screenshot quality", 1, 10, 1, 0,
            "Höhere Werte ergeben größere Dateien.", "Higher values create larger files."),
    }),
}

-- Ready-made sets. "values" lists exactly what a preset changes; everything else stays as it is.
-- Never touched by a preset: resolution, window mode, frame limits, VSync, gamma,
-- HDR (own preset), camera, nameplates, spell queue, screenshots and sound. Render scale and
-- sharpening strength are set by the beauty preset only; the resample filter is never touched by a
-- preset. giQuality stays out on purpose: low values break Forever's lighting and high ones were
-- reported to crash.
-- `summary` is shown before applying; it describes, it does not promise any FPS number. An entry is
-- a plain string or {text, needs = {names}}; the latter is only shown when the client offers all
-- of those settings (see G.PresetSummary).
NS.GraphicsPresets = {
    {
        key = "beauty",
        title = tr("Schöne Weitsicht", "Beautiful views"),
        hint = tr("Verbessert Sichtweite, Vegetation, Beleuchtung und Landschaftsdetails.",
            "Improves view distance, vegetation, lighting and landscape detail."),
        summary = {
            tr("Vegetation: dicht, weich ausgeblendet", "Vegetation: dense, soft fade"),
            tr("Sichtweite: maximal, wenig Aufploppen", "View distance: maximum, little pop-in"),
            tr("Licht: hoch statt Ultra", "Lighting: high instead of ultra"),
            tr("Texturen: 16× gefiltert, scharf", "Textures: 16× filtered, sharp"),
            {text = tr("Bild: 98 % Render-Skalierung, Schärfe 0,5", "Image: 98% render scale, sharpness 0.5"), needs = {"RenderScale", "ResampleSharpness"}},
        },
        values = {
            graphicsViewDistance = 9, graphicsEnvironmentDetail = 9,
            graphicsLightMode = 2, graphicsComputeEffects = 3,
            groundEffectDensity = 192, groundEffectDist = 400, groundEffectFade = 300,
            lodObjectFadeScale = 175, lodObjectCullSize = 8, doodadLodScale = 175, terrainLodDist = 800,
            horizonStart = 3000,
            shadowNumCascades = 4, shadowBlendCascades = 1, sunShafts = 2,
            textureFilteringMode = 5, terrainMipLevel = 0, ResampleAlwaysSharpen = 1,
            RenderScale = .98, ResampleSharpness = .5,
            reflectionMode = 3, rippleDetail = 2, weatherDensity = 3, projectedTextures = 1,
        },
    },
    {
        key = "fps",
        title = tr("Mehr FPS – gute Optik", "More FPS – good looks"),
        hint = tr("Reduziert aufwendige Grafikeffekte, ohne wichtige Bildqualität zu verlieren.",
            "Reduces expensive graphics effects without losing important image quality."),
        summary = {
            tr("Vegetation und Schatten: reduziert", "Vegetation and shadows: reduced"),
            tr("Licht und Nebel: günstiger", "Lighting and fog: cheaper"),
            tr("Texturen und Zaubereffekte: bleiben", "Textures and spell effects: stay"),
            tr("Auflösung: unverändert", "Resolution: unchanged"),
        },
        values = {
            graphicsViewDistance = 6, graphicsEnvironmentDetail = 5,
            graphicsLightMode = 1, graphicsComputeEffects = 1, graphicsShadowQuality = 2, graphicsSSAO = 1,
            volumeFog = 0,
            groundEffectDensity = 64, groundEffectDist = 160, groundEffectFade = 110,
            lodObjectFadeScale = 110, lodObjectCullSize = 14, doodadLodScale = 110, terrainLodDist = 500,
            shadowNumCascades = 2, sunShafts = 1,
            textureFilteringMode = 5, terrainMipLevel = 0, ResampleAlwaysSharpen = 1,
            reflectionMode = 1, rippleDetail = 1, projectedTextures = 1,
        },
    },
    {
        key = "hdr",
        title = tr("HDR einschalten", "Turn on HDR"),
        hint = tr("Nur für HDR-Monitore. Wird nach 30 Sekunden ohne Bestätigung zurückgesetzt.",
            "For HDR monitors only. Reverts after 30 seconds without confirmation."),
        values = {HDROutput = 1, HDRFactor = 1.3},
    },
}
