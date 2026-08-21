local M = {}
local BASE_URL = "https://mangadot.net"
local function attr(element, name) return element and element.attributes and element.attributes[name] end
local function clean(text) return stdlib.trim((tostring(text or ""):gsub("&amp;", "&"):gsub("&#039;", "'"):gsub("&quot;", '"'):gsub("%s+", " "))) end
local function absolute(url) return stdlib.url_join(BASE_URL, url or "") end
local function get(url) return http.get(url, { ["User-Agent"] = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36" }) end
local function origin_type(value)
    value = clean(value):upper()
    if value == "KR" then return "manhwa" end
    if value == "CN" then return "manhua" end
    if value == "JP" or value == "JA" then return "manga" end
    return ""
end
local function card_url(item)
    if item.slug then return absolute("/manga/" .. item.slug) end
    return absolute("/manga/" .. tostring(item.id or ""))
end
local function items_from_json(raw)
    local ok, data = pcall(json.parse, raw or "")
    if not ok or not data then return {} end
    local list = data.manga_list or data.results or data
    local results = {}
    for _, item in ipairs(list or {}) do
        local title = clean(item.title)
        if title ~= "" then
            local cover = absolute(item.photo or item.cover or item.thumbnail_url or "")
            local kind = origin_type(item.country_of_origin or item.origin or "")
            local url = card_url(item)
            if kind ~= "" then
                results[#results + 1] = { title = title, manga_title = title, url = url, manga_url = url,
                    thumbnail_url = cover, type = kind, sourceType = kind, source = "MangaDot", language = "en" }
            end
        end
    end
    return results
end
function M.search(params)
    params = params or {}
    local query = {
        q = params.query or params.title or "",
        page = params.page or 1,
        limit = params.limit or 20,
        sortBy = params.sort or "latest",
        sortOrder = "desc",
        strict_adult = 0
    }
    if query.q == "*" then query.q = "" end
    return items_from_json(get(BASE_URL .. "/api/search?" .. http.encode(query)))
end
function M.manga_details(url)
    url = absolute(url)
    local html = get(url)
    local title = clean((dom.select(html, "h1")[1] or {}).text or html:match('<meta property="og:title" content="([^"]+)"') or "")
    local image = html:match('<meta property="og:image" content="([^"]+)"') or html:match('src="([^"]*uploads/thumbs[^"]*)"') or ""
    local genres = {}
    for _, genre in ipairs(dom.select(html, 'a[href*="/genre"], a[href*="/tag"]')) do
        local value = clean(genre.text)
        if value ~= "" then genres[#genres + 1] = value end
    end
    local origin = html:match('"country_of_origin"%s*:%s*"([^"]+)"') or ""
    local kind = origin_type(origin)
    return { title = title, url = url, genres_json = json.encode(genres), thumbnail_url = absolute(image), type = kind, source = "MangaDot", language = "en" }
end
function M.chapters(manga_url)
    local html, results, seen = get(absolute(manga_url)), {}, {}
    for _, link in ipairs(dom.select(html, 'a[href*="/chapter"], a[href*="/read"]')) do
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
        if src and (src:find("/uploads/", 1, true) or src:find("/chapters/", 1, true)) then
            local page = absolute(src)
            if not seen[page] then seen[page] = true; results[#results + 1] = page end
        end
    end
    return results
end
function M.latest() return items_from_json(get(BASE_URL .. "/api/manga/section/latest-updates?page=1&limit=20")) end
function M.popular() return items_from_json(get(BASE_URL .. "/api/manga/section/most-tracked?page=1&limit=20")) end
return M
