local _, JLP = ...

local Theme = {
    assetRoot = "Interface\\AddOns\\JuztLevelProfessions\\Assets\\",
    colors = {
        window = {0.004, 0.012, 0.020, 1.00},
        sidebar = {0.008, 0.026, 0.042, 0.72},
        panel = {0.018, 0.050, 0.078, 0.92},
        panelAlt = {0.024, 0.068, 0.100, 0.92},
        border = {0.25, 0.43, 0.56, 0.92},
        cyan = {0.00, 0.70, 1.00, 1.0},
        blue = {0.02, 0.42, 0.76, 1.0},
        gold = {1.00, 0.67, 0.10, 1.0},
        text = {0.96, 0.97, 1.00, 1.0},
        muted = {0.61, 0.73, 0.82, 1.0},
        good = {0.30, 0.90, 0.48, 1.0},
        warn = {1.00, 0.65, 0.18, 1.0},
        bad = {1.00, 0.34, 0.30, 1.0},
    },
    layout = {
        width = 1360,
        height = 760,
        headerHeight = 92,
        sidebarWidth = 250,
        contentInset = 16,
        cardGap = 14,
        minScale = 0.65,
        maxScale = 1.30,
    },
    -- Fixed layout tokens are the UI equivalent of CSS spacing / sizing rules.
    -- Scaling changes the whole window uniformly; internal geometry stays stable.
    gathering = {
        -- Right-side dock geometry; never anchored across the map canvas.
        dockWidth=228,dockInset=8,dockScrollStep=35,
        dockContentHeight=438,dockScrollTop=38,dockScrollFooter=55,
        -- Relative distances within one scroll child; collapses never place
        -- controls over the map canvas or above Generate/Cancel.
        dockResourcesHeight=64,dockResourcesExpandedHeight=460,
        dockResourceSearchTop=38,dockResourceTabsTop=72,dockResourceInfoTop=101,
        dockResourceRowsTop=126,dockResourcePagerTop=376,dockResourceSelectTop=417,
        dockRouteExpandedHeight=194,dockRouteCollapsedHeight=30,
        dockRouteActionTop=156,dockRouteActionWidth=92,
        dockDisplayExpandedHeight=146,dockDisplayCollapsedHeight=30,
        dockMinViewport=40,dockButtonWidth=84,dockScrollButtonHeight=22,
        legend="Historical references: possible locations, not live spawns. Personal pins: past successful gathers.",
        mapDisplayModes={"COMPACT","SELECTED","DETAILED"},
        -- Logical UI-units; shared geometry / text feedback spacing.
        statusLeft=22, statusRight=22, feedbackButton=119, feedbackGap=12,
        resourceRowHeight=29, compactGlyphFallback="-",
        overlayInset=22, overlayTop=80, overlayFooter=12, pickerTop=179,
        pickerRowTop=128, pickerRowHeight=25, pickerRowStride=27,
        pickerPagerHeight=24, pickerPagerBottom=14, pickerPagerGap=8,
        -- Embedded picker: a single source for measured logical (not pixel) bounds.
        pickerInset=14, pickerPreferredLeft=358, pickerPreferredWidth=365,
        pickerPreferredHeight=350, pickerMinContentWidth=346,
        pickerFooterAllowance=12, pickerMaxRows=6,
        pickerSearchWidth=325, pickerResourceButtonWidth=326,
        feedbackTone={READY="good",GENERATING="cyan",ERROR="bad",
            CANCELLED="warn",EMPTY="muted",REJECTED="warn",IDLE="muted"},
    },
    secondaryMaterial = {
        pagerTop=532, pagerLabelTop=570, pagerInset=22, pagerButtonWidth=90,
        pagerButtonHeight=28, cardValueWidth=350,
    },
    overview = {
        contentWidth = 1078,
        contentHeight = 636,
        topHeight = 376,
        bottomHeight = 246,
        progressWidth = 450,
        lowerWidth = 350,
        gap = 14,
        cardContentTop = 58,
        cardContentBottom = 12,
        cardContentLeft = 22,
        cardContentRight = 12,
        scrollbarGutter = 12,
        rowHeight = 20,
        materialRowHeight = 74,
        materialRowGap = 8,
    },
    nav = {
        { key = "Overview", label = "Overview", icon = "icons\\overview.tga" },
        { key = "Guide", label = "Profession Guide", icon = "icons\\guide.tga" },
        { key = "Auction House", label = "Auction House", icon = "icons\\professions.tga" },
        { key = "Bank", label = "Bank", icon = "icons\\bank.tga" },
        { key = "History", label = "Crafting History", icon = "icons\\guide.tga" },
        { key = "Settings", label = "Settings", icon = "icons\\settings.tga" },
    },
}

function Theme:Color(name)
    local c = self.colors[name] or self.colors.text
    return c[1], c[2], c[3], c[4]
end

function Theme:Asset(relative)
    return self.assetRoot .. tostring(relative or "")
end

JLP.UITheme = Theme
