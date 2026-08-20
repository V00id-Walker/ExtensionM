local M = {}
local BASE_URL = "https://projectsuki.com"
local function attr(element, name) return element and element.attributes and element.attributes[name] end
local function clean(text) return stdlib.trim(((text or ""):gsub("&amp;", "&"):gsub("&#039;", "'"):gsub("&quot;", '"'):gsub("%s+", " "))) end
local function absolute(url) return stdlib.url_join(BASE_URL, url or "") end
local function get(url) return http.get(url, { ["User-Agent"] = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36" }) end
local function infer_type(title)
    local lower = (title or ""):lower()
    if lower:find("nano machine", 1, true) or lower:find("logging 10,000 years", 1, true) or lower:find("demonic emperor", 1, true) then return "manhua" end
    if lower:find("deadbeat noble", 1, true) or lower:find("solo max-level", 1, true) or lower:find("mount hua", 1, true) then return "manhwa" end
    return "manga"
end
local function cards(html)
    local results, seen = {}, {}
    for _, link in ipairs(dom.select(html, 'a[href*="/book/"]')) do
        local href = attr(link, "href")
        local title = clean(attr(link, "title") or link.text)
        local url = href and absolute(href)
        if url and title ~= "" and not seen[url] then
            local block = html:match('href="' .. href:gsub("([^%w])", "%%%1") .. '".-</a>') or ""
            local image = block:match('src="([^"]+)"') or html:match('href="' .. href:gsub("([^%w])", "%%%1") .. '".-src="([^"]+)"') or ""
            seen[url] = true
            local cover = absolute(image)
            local kind = infer_type(title)
            results[#results + 1] = { title = title, manga_title = title, url = url, manga_url = url,
                thumbnail_url = cover, type = kind, sourceType = kind,
                source = "Project Suki", language = "en" }
        end
    end
    return results
end
function M.search(params)
    params = params or {}
    local query = params.query or params.title or ""
    return cards(get(BASE_URL .. "/browse?" .. http.encode({ title = query })))
end
function M.manga_details(url)
    url = absolute(url)
    local html = get(url)
    local title = clean((dom.select(html, "h1")[1] or {}).text or html:match('<meta property="og:title" content="([^"]+)"') or "")
    local image = html:match('<meta property="og:image" content="([^"]+)"') or html:match('src="([^"]*gallery[^"]*)"') or ""
    local description = clean((dom.select(html, ".description, #description, p")[1] or {}).text or "")
    local genres = {}
    for _, genre in ipairs(dom.select(html, 'a[href*="/tag/"], a[href*="/genre/"]')) do
        local value = clean(genre.text)
        if value ~= "" then genres[#genres + 1] = value end
    end
    return { title = title, url = url, description = description, genres_json = json.encode(genres),
        thumbnail_url = absolute(image), type = infer_type(title), source = "Project Suki", language = "en" }
end
function M.chapters(manga_url)
    local html, results, seen = get(absolute(manga_url)), {}, {}
    for _, link in ipairs(dom.select(html, 'a[href*="/read/"]')) do
        local href = attr(link, "href")
        local url = href and absolute(href)
        if url and not seen[url] then
            seen[url] = true
            local label = clean(attr(link, "title") or link.text)
            local number = label:match("[Cc]hapter%s*([%d%.]+)") or href:match("/read/[^/]+/[^/]+/([^/?#]+)")
            results[#results + 1] = { source_url = url, name = label ~= "" and label or "Chapter", chapter_number = number, language = "en" }
        end
    end
    return results
end
function M.pages(chapter_url)
    local html, results, seen = get(absolute(chapter_url)), {}, {}
    for _, image in ipairs(dom.select(html, "img")) do
        local src = attr(image, "src") or attr(image, "data-src")
        if src and src:find("/images/", 1, true) then
            local page = absolute(src)
            if not seen[page] then seen[page] = true; results[#results + 1] = page end
        end
    end
    return results
end
function M.latest() return cards(get(BASE_URL .. "/")) end
function M.popular() return cards(get(BASE_URL .. "/browse")) end
return M
