local M = {}
local BASE_URL = "https://asurascans.com"
local function blob(doc, name)
    local el = doc:select_one('astro-island[component-url*="' .. name .. '"]')
        or doc:select_one('script[data-name="' .. name .. '"]')
    if not el then return nil end
    local raw = el:attr("props") or el:text()
    local ok, data = pcall(json.parse, raw)
    return ok and data or nil
end
local function value(pair) return pair and pair[2] end
local function cards(doc)
    local results = {}
    for _, card in ipairs(doc:select_all("[data-series-id]")) do
        local link, title, image = card:select_one('a[href*="/comics/"]'), card:select_one("h3"), card:select_one("img")
        local status, count = card:select_one('[data-status], a[href*="status="]'), card:select_one("span")
        if link and title then results[#results + 1] = {
            title = title:text(), url = stdlib.url_join(BASE_URL, link:attr("href")),
            thumbnail_url = image and stdlib.url_join(BASE_URL, image:attr("src") or image:attr("data-src") or "") or "",
            status = status and status:text():lower() or "", chapter_count = count and tonumber(count:text()) or nil,
        } end
    end
    return results
end
function M.search(params)
    params = params or {}
    local query = { search = params.query or params.title, author = params.author, status = params.status,
        type = params.type, order = params.order or "update", page = params.page or 1 }
    return cards(dom.fetch(BASE_URL .. "/browse/comics?" .. http.encode(query)))
end
function M.manga_details(url)
    url = stdlib.url_join(BASE_URL, url)
    local doc, genres = dom.fetch(url), {}
    for _, el in ipairs(doc:select_all('a[href*="genres="]')) do genres[#genres + 1] = el:text() end
    local function text(selector) local el = doc:select_one(selector); return el and el:text() or "" end
    local image, canonical = doc:select_one('meta[property="og:image"]'), doc:select_one('link[rel="canonical"]')
    return { title = text("h1"), url = canonical and stdlib.url_join(BASE_URL, canonical:attr("href")) or url,
        author = text('a[href*="author="]'), artist = text('a[href*="artist="]'),
        description = text("#description-text"), genres_json = json.encode(genres),
        status = text('a[href*="status="]'):lower(), thumbnail_url = image and stdlib.url_join(BASE_URL, image:attr("content")) or "",
        type = text('a[href*="type="]'):lower() }
end
function M.chapters(manga_url)
    manga_url = stdlib.url_join(BASE_URL, manga_url)
    local data, results = blob(dom.fetch(manga_url), "ChapterList") or {}, {}
    local list = value(data.chapters) or {}
    local series_url = value(data.publicUrl) or "/comics/" .. (value(data.seriesSlug) or manga_url:match("/comics/([^/?#]+)"))
    for _, wrapped in ipairs(list) do
        local chapter, number = value(wrapped), value(value(wrapped).number)
        local name = "Chapter " .. tostring(number)
        local title = value(chapter.title)
        if title and title ~= "" then name = name .. ": " .. title end
        results[#results + 1] = { source_url = stdlib.url_join(BASE_URL, series_url .. "/chapter/" .. number),
            name = name, chapter_number = tostring(number), scanlator = "Asura Scans", language = "en",
            page_count = value(chapter.page_count), upload_date = value(chapter.published_at) and stdlib.parse_date(value(chapter.published_at)) or nil }
    end
    return results
end
function M.pages(chapter_url)
    local data = blob(dom.fetch(stdlib.url_join(BASE_URL, chapter_url)), "ChapterReader") or {}
    local results = {}
    for _, wrapped in ipairs(value(data.pages) or {}) do
        results[#results + 1] = stdlib.url_join(BASE_URL, value(value(wrapped).url))
    end
    return results
end
function M.latest()
    local data, results = blob(dom.fetch(BASE_URL .. "/comics"), "LatestUpdates") or {}, {}
    for _, wrapped in ipairs(value(data.chapters) or {}) do
        local item, number = value(wrapped), value(value(wrapped).number)
        results[#results + 1] = { manga_title = value(item.comic_name), manga_url = stdlib.url_join(BASE_URL, value(item.comic_public_url)),
            thumbnail_url = stdlib.url_join(BASE_URL, value(item.comic_cover) or ""), chapter_name = value(item.title) or "Chapter " .. tostring(number),
            chapter_number = tostring(number), upload_date = value(item.published_at) and stdlib.parse_date(value(item.published_at)) or nil }
    end
    return results
end
function M.popular()
    return cards(dom.fetch(BASE_URL .. "/browse/comics?order=popular"))
end
return M
