local _, NS = ...
local tr = NS.Text

-- Console settings the addon may touch, nothing else. The client decides which exist:
-- rows without a matching console variable stay hidden, so the list cannot go stale.
-- cost: 0 none, 1 low, 2 medium, 3 high (rough FPS impact, not a measurement).
local function range(name, de, en, minimum, maximum, step, cost, dd, de2)
    return {name = name, title = tr(de, en), kind = "range", minimum = minimum, maximum = maximum, step = step, cost = cost, hint = tr(dd, de2)}
end
local function toggle(name, de, en, cost, dd, de2)
    return {name = name, title = tr(de, en), kind = "toggle", cost = cost, hint = tr(dd, de2)}
end
local function group(key, de, en, rows)
    return {key = key, title = tr(de, en), rows = rows}
end

NS.GraphicsCatalog = {
    group("distance", "Sichtweite und Aufploppen", "View distance and pop-in", {
        range("lodObjectFadeScale", "Objekte ausblenden ab", "Object fade distance", 25, 300, 5, 2,
            "Höhere Werte blenden Objekte später aus.", "Higher values fade objects out later."),
        range("lodObjectCullSize", "Kleinste sichtbare Objekte", "Smallest visible objects", 1, 40, 1, 2,
            "Niedrigere Werte zeichnen auch kleine Objekte in der Ferne.", "Lower values also draw small objects far away."),
        range("doodadLodScale", "Detailstufe von Dekoration", "Decoration detail", 25, 300, 5, 2,
            "Höhere Werte halten Kisten, Zäune und Felsen länger detailreich.", "Higher values keep crates, fences and rocks detailed for longer."),
        range("terrainLodDist", "Detailstufe des Geländes", "Terrain detail distance", 100, 1500, 50, 3,
            "", ""),
        range("entityLodDist", "Detailstufe von Figuren", "Character detail distance", 100, 1500, 50, 2,
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
    group("shadows", "Schatten und Licht", "Shadows and lighting", {
        range("shadowNumCascades", "Schattenstufen", "Shadow cascades", 1, 4, 1, 3,
            "Mehr Stufen ergeben scharfe Schatten auch in der Ferne.", "More cascades keep shadows sharp in the distance."),
        toggle("shadowSoft", "Weiche Schatten", "Soft shadows", 2,
            "", ""),
        toggle("sunShafts", "Sonnenstrahlen", "Sun shafts", 2,
            "Sichtbare Lichtstrahlen durch Bäume und Wolken.", "Visible light rays through trees and clouds."),
    }),
    group("image", "Bildschärfe", "Image sharpness", {
        toggle("ResampleAlwaysSharpen", "Immer nachschärfen", "Always sharpen", 0,
            "Schärft das Bild auch bei voller Renderauflösung.", "Sharpens the image even at full render resolution."),
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
            "Nur mit HDR-Monitor sinnvoll. Kann einen Neustart des Spiels brauchen.", "Only useful with an HDR monitor. May need a game restart."),
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

-- Ready-made sets. "values" lists exactly what a preset changes.
NS.GraphicsPresets = {
    {
        key = "beauty",
        title = tr("Empfohlen: schöne Weitsicht", "Recommended: beautiful views"),
        hint = tr("Dichtes Gras, weite Sicht und scharfe Schatten. Braucht einen kräftigen Rechner.",
            "Dense grass, long view distance and sharp shadows. Needs a capable computer."),
        values = {
            groundEffectDensity = 256, groundEffectFade = 370, groundEffectDist = 500,
            lodObjectFadeScale = 200, lodObjectCullSize = 8, doodadLodScale = 200, terrainLodDist = 1000,
            ResampleAlwaysSharpen = 1, shadowNumCascades = 4,
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
