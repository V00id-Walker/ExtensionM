local M = {}

local BASE_URL = "https://comix.to"
local API_URL = BASE_URL .. "/api/v1"

local function trim(value)
    return stdlib.trim(tostring(value or ""))
end

local function absolute(url)
    url = trim(url)
    if url == "" then return "" end
    return stdlib.url_join(BASE_URL, url)
end

local function title_url(manga)
    local url = trim(manga.url)
    if url ~= "" then return absolute(url) end
    local hid = trim(manga.hid)
    if hid ~= "" then return BASE_URL .. "/title/" .. hid end
    return BASE_URL
end

local function poster_url(manga)
    local poster = manga.poster or {}
    return trim(poster.large or poster.medium or poster.small or manga.thumbnail_url or "")
end

local function source_type(value)
    value = trim(value):lower()
    if value == "manhwa" then return "manhwa" end
    if value == "manhua" then return "manhua" end
    if value == "manga" then return "manga" end
    return ""
end

local function manga_card(manga)
    local title = trim(manga.title)
    local url = title_url(manga)
    local kind = source_type(manga.type)
    local cover = poster_url(manga)
    if kind == "" then return nil end
    return {
        title = title,
        manga_title = title,
        url = url,
        manga_url = url,
        thumbnail_url = cover,
        type = kind,
        sourceType = kind,
        source = "Comix",
        language = "en",
    }
end

local function cards(payload)
    local list = payload.items or (payload.result and payload.result.items) or payload
    local results = {}
    if type(list) ~= "table" then return results end
    for _, manga in ipairs(list) do
        if trim(manga.title) ~= "" then
            local card = manga_card(manga)
            if card then results[#results + 1] = card end
        end
    end
    return results
end

local function capture(url, kind)
    local raw = http.webview_json(url, kind)
    if raw == "" then return {} end
    return json.decode(raw)
end

local function browse_url(params)
    return API_URL .. "/manga?" .. http.encode(params or {})
end

function M.search(params)
    params = params or {}
    local query = trim(params.query or params.title)
    return cards(capture(browse_url({ keyword = query }), "browse"))
end

function M.popular()
    return cards(capture(BASE_URL .. "/browse?order[score]=desc", "browse"))
end

function M.latest()
    return cards(capture(BASE_URL .. "/browse?order[chapter_updated_at]=desc", "browse"))
end

function M.manga_details(url)
    local manga = capture(absolute(url), "details")
    local genres = {}
    local kind = source_type(manga.type)
    genres[#genres + 1] = kind
    for _, group in ipairs({ manga.genres or manga.genre or {}, manga.demographics or manga.demographic or {} }) do
        for _, item in ipairs(group) do
            local value = trim(item.title)
            if value ~= "" then genres[#genres + 1] = value end
        end
    end
    local card = manga_card(manga)
    card.description = trim(manga.synopsis)
    card.genres_json = json.encode(genres)
    return card
end

local function chapter_name(chapter)
    local number = trim(chapter.number)
    local name = trim(chapter.name)
    if name ~= "" and number ~= "" then return "Chapter " .. number .. ": " .. name end
    if name ~= "" then return name end
    if number ~= "" then return "Chapter " .. number end
    return "Chapter"
end

function M.chapters(manga_url)
    local chapters = capture(absolute(manga_url), "chapters")
    local results = {}
    for _, chapter in ipairs(chapters) do
        local chapter_url = trim(chapter.url)
        if chapter_url ~= "" then
            results[#results + 1] = {
                source_url = absolute(chapter_url),
                name = chapter_name(chapter),
                chapter_number = chapter.number,
                language = "en",
            }
        end
    end
    return results
end

function M.pages(chapter_url)
    local payload = capture(absolute(chapter_url), "pages")
    local base = trim(payload.baseUrl or payload.base_url):gsub("/$", "")
    local items = payload.items or {}
    local results = {}
    for _, page in ipairs(items) do
        local image = trim(page.url)
        if image ~= "" then
            if not image:match("^https?://") then
                image = base .. "/" .. image:gsub("^/", "")
            end
            results[#results + 1] = image
        end
    end
    return results
end

return M
