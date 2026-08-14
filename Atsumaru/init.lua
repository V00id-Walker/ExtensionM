local M = {}
local BASE_URL = "https://atsu.moe"

local function first(html, selector) return dom.select(html, selector)[1] end
local function attr(element, name) return element and element.attributes and element.attributes[name] end
local function clean(text)
    return stdlib.trim(((text or ""):gsub("&amp;", "&"):gsub("&#039;", "'"):gsub("&quot;", '"'):gsub("%s+", " ")))
end
local function absolute(url) return stdlib.url_join(BASE_URL, url or "") end

local function add_result(results, seen, title, href, image)
    local url = href and absolute(href) or nil
    title = clean(title)
    if url and title ~= "" and url:find("/manga/", 1, true) and not seen[url] then
        seen[url] = true
        results[#results + 1] = {
            title = title,
            manga_title = title,
            url = url,
            manga_url = url,
            thumbnail_url = absolute(image or ""),
            source = "Atsumaru",
            language = "en"
        }
    end
end

local function html_results(html)
    local results, seen = {}, {}
    for _, link in ipairs(dom.select(html, 'a[href*="/manga/"]')) do
        add_result(results, seen, link.text, attr(link, "href"), nil)
    end
    return results
end

local function json_results(raw)
    local ok, data = pcall(json.parse, raw)
    if not ok or not data then return {} end
    local rows = data.results or data.items or data.documents or data.manga or data.data or data
    local results, seen = {}, {}
    for _, item in ipairs(rows) do
        local id = item.id or item.slug or item.mangaId or item.anilistId or item.malId
        local title = item.title or item.name or item.romaji or item.english
        if type(title) == "table" then title = title.english or title.romaji or title.native or title.userPreferred end
        local href = item.url or (id and ("/manga/" .. id))
        local image = item.coverImage or item.thumbnail or item.image or item.poster
        if type(image) == "table" then image = image.extraLarge or image.large or image.medium or image.url end
        add_result(results, seen, title, href, image)
    end
    return results
end

function M.search(params)
    params = params or {}
    local query = params.query or params.title or ""
    local ok, api = pcall(http.get, BASE_URL .. "/api/search/manga?" .. http.encode({ q = query, page = params.page or 1 }))
    local results = ok and json_results(api) or {}
    if #results > 0 then return results end
    return html_results(http.get(BASE_URL .. "/search?" .. http.encode({ q = query })))
end

function M.manga_details(url)
    url = absolute(url)
    local html = http.get(url)
    local title = first(html, "h1") or first(html, 'meta[property="og:title"]')
    local image = first(html, 'meta[property="og:image"]')
    local description = first(html, 'meta[name="description"]') or first(html, 'meta[property="og:description"]')
    local canonical = first(html, 'link[rel="canonical"]')
    local genres = {}
    for _, genre in ipairs(dom.select(html, 'a[href*="genre"], a[href*="tag"]')) do
        local value = clean(genre.text)
        if value ~= "" then genres[#genres + 1] = value end
    end
    local plain = clean(html:gsub("<[^>]->", " "))
    return {
        title = clean(title and (title.text or attr(title, "content")) or ""),
        url = canonical and absolute(attr(canonical, "href")) or url,
        description = clean(description and attr(description, "content") or ""),
        genres_json = json.encode(genres),
        status = clean(plain:match("Status%s+([%a%s%-_]+)%s+") or ""),
        thumbnail_url = absolute(image and attr(image, "content") or ""),
        source = "Atsumaru",
        language = "en"
    }
end

function M.chapters(manga_url)
    manga_url = absolute(manga_url)
    local html = http.get(manga_url)
    local results, seen = {}, {}
    for _, link in ipairs(dom.select(html, 'a[href*="/read/"], a[href*="/chapter/"]')) do
        local href = attr(link, "href")
        if href then
            local url = absolute(href)
            if not seen[url] then
                seen[url] = true
                local text = clean(link.text)
                local number = text:match("[Cc]hapter%s*([%d%.]+)") or href:match("[Cc]hapter[/%-]([%d%.]+)") or href:match("/read/[^/]+/([%d%.]+)")
                results[#results + 1] = {
                    source_url = url,
                    name = text ~= "" and text or (number and ("Chapter " .. number) or "Chapter"),
                    chapter_number = number,
                    language = "en"
                }
            end
        end
    end
    return results
end

function M.pages(chapter_url)
    local html = http.get(absolute(chapter_url))
    local results, seen = {}, {}
    for _, image in ipairs(dom.select(html, "img")) do
        local src = attr(image, "src") or attr(image, "data-src")
        if src and (src:find("cdn.atsu.moe", 1, true) or src:find("/media/", 1, true) or src:find("/page", 1, true)) then
            local url = absolute(src)
            if not seen[url] then seen[url] = true; results[#results + 1] = url end
        end
    end
    for url in html:gmatch('https?://cdn%.atsu%.moe/[^"\'%s<>\\]+') do
        if not seen[url] then seen[url] = true; results[#results + 1] = url:gsub("\\/", "/") end
    end
    return results
end

function M.latest() return html_results(http.get(BASE_URL .. "/")) end
function M.popular() return html_results(http.get(BASE_URL .. "/")) end

return M
