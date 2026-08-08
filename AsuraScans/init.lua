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
local function linked_cards(doc)
    local results, seen = {}, {}
    for _, link in ipairs(doc:select_all('a[href*="/comics/"]')) do
        local href, image = link:attr("href"), link:select_one("img")
        if href and not href:find("/chapter/", 1, true) and image then
            local url = stdlib.url_join(BASE_URL, href)
            local title = image:attr("alt") or image:attr("title") or ""
            if title ~= "" and not seen[url] then
                seen[url] = true
                results[#results + 1] = { title = title, manga_title = title, url = url, manga_url = url,
                    thumbnail_url = stdlib.url_join(BASE_URL, image:attr("src") or image:attr("data-src") or "") }
            end
        end
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
    local doc, results, seen = dom.fetch(manga_url), {}, {}
    for _, link in ipairs(doc:select_all('a[href*="/chapter/"]')) do
        local href = link:attr("href")
        if href then
            local url, number = stdlib.url_join(BASE_URL, href), href:match("/chapter/([^/?#]+)")
            if number and not seen[url] then
                seen[url] = true
                local label = link:text():match("Chapter[^\n]*") or "Chapter " .. number
                results[#results + 1] = { source_url = url, name = stdlib.trim(label), chapter_number = number,
                    scanlator = "Asura Scans", language = "en" }
            end
        end
    end
    return results
end
function M.pages(chapter_url)
    local doc, results = dom.fetch(stdlib.url_join(BASE_URL, chapter_url)), {}
    for _, image in ipairs(doc:select_all("img[data-page-index]")) do
        local src = image:attr("src") or image:attr("data-src")
        if src then results[#results + 1] = stdlib.url_join(BASE_URL, src) end
    end
    return results
end
function M.latest()
    return linked_cards(dom.fetch(BASE_URL .. "/comics"))
end
function M.popular()
    return cards(dom.fetch(BASE_URL .. "/browse/comics?order=popular"))
end
return M
