local M = {}
local BASE_URL = "https://mangaball.net"
local function attr(element, name) return element and element.attributes and element.attributes[name] end
local function clean(text) return stdlib.trim(((text or ""):gsub("&amp;", "&"):gsub("&#039;", "'"):gsub("&quot;", '"'):gsub("%s+", " "))) end
local function absolute(url) return stdlib.url_join(BASE_URL, url or "") end
local function get(url) return http.get(url, { ["User-Agent"] = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36" }) end
local function normalize_type(value)
    value = clean(value):lower()
    if value:find("manhwa", 1, true) then return "manhwa" end
    if value:find("manhua", 1, true) then return "manhua" end
    if value:find("manga", 1, true) then return "manga" end
    return ""
end
local function extract_type(html)
    html = html or ""
    local value = html:match("[Tt]ype%s*</[^>]+>%s*<[^>]+>%s*([^<]+)")
        or html:match("[Tt]ype%s*:%s*([^<\n]+)")
        or html:match('href="[^"]*[Tt]ype[^"]*"[^>]*>([^<]+)')
    return normalize_type(value)
end
local function detail_type(url)
    local ok, html = pcall(get, absolute(url))
    if not ok or not html then return "" end
    return extract_type(html)
end
local function cards(html)
    local results, seen = {}, {}
    for _, link in ipairs(dom.select(html, 'a[href*="/title/"], a[href*="/series/"], a[href*="/manga/"]')) do
        local href = attr(link, "href")
        local url = href and absolute(href)
        local title = clean(attr(link, "title") or link.text)
        if title == "" then
            local block = html:match('href="' .. href:gsub("([^%w])", "%%%1") .. '".-</a>') or ""
            title = clean(block:match('alt="([^"]+)"') or "")
        end
        if url and title ~= "" and not seen[url] then
            local block = html:match('href="' .. href:gsub("([^%w])", "%%%1") .. '".-</a>') or ""
            local image = block:match('src="([^"]+)"') or ""
            seen[url] = true
            local cover = absolute(image)
            local kind = detail_type(url)
            if kind ~= "" then
                results[#results + 1] = { title = title, manga_title = title, url = url, manga_url = url,
                    thumbnail_url = cover, type = kind, sourceType = kind, source = "MangaBall", language = "en" }
            end
        end
    end
    return results
end
function M.search(params)
    params = params or {}
    return cards(get(BASE_URL .. "/search?" .. http.encode({ q = params.query or params.title or "" })))
end
function M.manga_details(url)
    url = absolute(url)
    local html = get(url)
    local title = clean((dom.select(html, "h1")[1] or {}).text or html:match('<meta property="og:title" content="([^"]+)"') or "")
    local image = html:match('<meta property="og:image" content="([^"]+)"') or html:match('src="([^"]*cover[^"]*)"') or ""
    local genres = {}
    for _, genre in ipairs(dom.select(html, 'a[href*="/genres/"], a[href*="/genre/"], a[href*="/tag/"]')) do
        local value = clean(genre.text)
        if value ~= "" then genres[#genres + 1] = value end
    end
    local kind = extract_type(html)
    return { title = title, url = url, genres_json = json.encode(genres), thumbnail_url = absolute(image), type = kind, source = "MangaBall", language = "en" }
end
function M.chapters(manga_url)
    local html, results, seen = get(absolute(manga_url)), {}, {}
    for _, link in ipairs(dom.select(html, 'a[href*="/chapter/"], a[href*="/read/"]')) do
        local href = attr(link, "href")
        local url = href and absolute(href)
        if url and not seen[url] then
            seen[url] = true
            local label = clean(attr(link, "title") or link.text)
            results[#results + 1] = { source_url = url, name = label ~= "" and label or "Chapter", chapter_number = label:match("[Cc]hapter%s*([%d%.]+)"), language = "en" }
        end
    end
    return results
end
function M.pages(chapter_url)
    local html, results, seen = get(absolute(chapter_url)), {}, {}
    for _, image in ipairs(dom.select(html, "img")) do
        local src = attr(image, "src") or attr(image, "data-src")
        if src and not src:find("/frontend/images/", 1, true) then
            local page = absolute(src)
            if not seen[page] then seen[page] = true; results[#results + 1] = page end
        end
    end
    return results
end
function M.latest() return cards(get(BASE_URL .. "/recently-updated/")) end
function M.popular() return cards(get(BASE_URL .. "/popular/")) end
return M
