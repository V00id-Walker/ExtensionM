local M = {}
local BASE_URL = "https://asurascans.com"
local function value(pair) return pair and pair[2] end
local function first(html, selector)
    return dom.select(html, selector)[1]
end
local function attr(element, name)
    return element and element.attributes and element.attributes[name]
end
local function blob(html, name)
    local el = first(html, 'astro-island[component-url*="' .. name .. '"]')
        or first(html, 'script[data-name="' .. name .. '"]')
    if not el then return nil end
    local raw = attr(el, "props") or el.text
    local ok, data = pcall(json.parse, raw)
    return ok and data or nil
end
local function page_text(html)
    return stdlib.trim((html:gsub("<[^>]->", " "):gsub("%s+", " ")))
end
local function normalize_type(value)
    value = stdlib.trim((value or ""):lower())
    if value == "manhua" or value == "manhwa" or value == "manga" then return value end
    return ""
end
local function detail_type(url)
    local ok, html = pcall(http.get, stdlib.url_join(BASE_URL, url or ""))
    if not ok or not html then return "" end
    local plain = page_text(html)
    local series_type = plain:match("Type%s+([%a%s_-]+)%s+Author")
    if not series_type then
        local el = first(html, 'a[href*="type="]')
        series_type = el and el.text or ""
    end
    return normalize_type(series_type)
end
local function paired_cards(html, link_selector, image_selector)
    local results, links, images = {}, dom.select(html, link_selector), dom.select(html, image_selector)
    for index, link in ipairs(links) do
        local image, href = images[index], attr(link, "href")
        local title = attr(image, "alt") or ""
        if href and title ~= "" then
            local url = stdlib.url_join(BASE_URL, href)
            local cover = stdlib.url_join(BASE_URL, attr(image, "src") or attr(image, "data-src") or "")
            local series_type = detail_type(url)
            if series_type ~= "" then
                results[#results + 1] = {
                title = title, manga_title = title,
                url = url, manga_url = url,
                thumbnail_url = cover,
                type = series_type, sourceType = series_type,
            } end
        end
    end
    return results
end
local function html_unescape(value)
    value = value or ""
    return (value:gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"))
end
local function embedded_browse_cards(html)
    local results, seen = {}, {}
    for block in html:gmatch("&quot;id&quot;:%[0,%d+%](.-)&quot;latest_chapters&quot;") do
        local title = html_unescape(block:match("&quot;title&quot;:%[0,&quot;(.-)&quot;%]"))
        local cover = html_unescape(block:match("&quot;cover&quot;:%[0,&quot;(https://.-)&quot;%]"))
        local url = html_unescape(block:match("&quot;public_url&quot;:%[0,&quot;(.-)&quot;%]"))
        local series_type = normalize_type(html_unescape(block:match("&quot;type&quot;:%[0,&quot;(.-)&quot;%]")))
        if title ~= "" and cover ~= "" and url ~= "" and series_type ~= "" and not seen[url] then
            seen[url] = true
            results[#results + 1] = {
                title = title, manga_title = title,
                url = stdlib.url_join(BASE_URL, url), manga_url = stdlib.url_join(BASE_URL, url),
                thumbnail_url = cover,
                type = series_type, sourceType = series_type,
            }
        end
    end
    return results
end
local function browse(params)
    params = params or {}
    local query = {
        search = params.query or params.title,
        author = params.author,
        status = params.status,
        type = params.type,
        page = params.page or 1
    }
    local order = params.order or params.sort
    if order == "popular" or order == "views" or order == "most_viewed" then
        query.sort = "popular"
    elseif order == "latest" or order == "update" or order == "recently_updated" then
        query.sort = "latest"
    end
    if query.search == "*" then query.search = nil end
    local html = http.get(BASE_URL .. "/browse/comics?" .. http.encode(query))
    local results = embedded_browse_cards(html)
    if #results > 0 then return results end
    results = paired_cards(html, '[data-series-id] > a[href*="/comics/"]', '[data-series-id] > a[href*="/comics/"] img')
    if #results == 0 then
        results = paired_cards(html, 'a[href*="/comics/"]', 'a[href*="/comics/"] img')
    end
    return results
end
function M.search(params)
    return browse(params)
end
function M.manga_details(url)
    url = stdlib.url_join(BASE_URL, url)
    local html, genres = http.get(url), {}
    for _, el in ipairs(dom.select(html, 'a[href*="genres="]')) do genres[#genres + 1] = stdlib.trim(el.text or "") end
    local function text(selector) local el = first(html, selector); return el and stdlib.trim(el.text or "") or "" end
    local image, canonical = first(html, 'meta[property="og:image"]'), first(html, 'link[rel="canonical"]')
    local plain = page_text(html)
    local status = plain:match("Status%s+([%a%s_-]+)%s+Type") or text('a[href*="status="]')
    local series_type = plain:match("Type%s+([%a%s_-]+)%s+Author") or text('a[href*="type="]')
    return { title = text("h1"), url = canonical and stdlib.url_join(BASE_URL, attr(canonical, "href")) or url,
        author = text('a[href*="author="]'), artist = text('a[href*="artist="]'),
        description = text("#description-text"), genres_json = json.encode(genres),
        status = stdlib.trim(status or ""):lower(), thumbnail_url = image and stdlib.url_join(BASE_URL, attr(image, "content")) or "",
        type = stdlib.trim(series_type or ""):lower() }
end
function M.chapters(manga_url)
    manga_url = stdlib.url_join(BASE_URL, manga_url)
    local html, results, seen = http.get(manga_url), {}, {}
    for _, link in ipairs(dom.select(html, 'a[href*="/chapter/"]')) do
        local href = attr(link, "href")
        if href then
            local url, number = stdlib.url_join(BASE_URL, href), href:match("/chapter/([^/?#]+)")
            if number and not seen[url] then
                seen[url] = true
                local raw = stdlib.trim((link.text or ""):gsub("%s+", " "))
                local after_number = stdlib.trim(raw:match("[Cc]hapter%s*" .. number .. "(.*)") or "")
                local time = after_number:match("(%d+%s*minutes?%s+ago)$")
                    or after_number:match("(%d+%s*hours?%s+ago)$")
                    or after_number:match("(%d+%s*days?%s+ago)$")
                    or after_number:match("(%d+%s*weeks?%s+ago)$")
                    or after_number:match("(%d+%s*months?%s+ago)$")
                    or after_number:match("(%d+%s*years?%s+ago)$")
                    or after_number:match("([A-Z][a-z][a-z]%s+%d+,?%s+%d%d%d%d)$")
                    or after_number:match("([A-Z][a-z][a-z]%s+%d%d?)$")
                    or after_number:match("(yesterday)$")
                    or after_number:match("(today)$")
                    or after_number:match("(last week)$")
                local extra = after_number
                if time then
                    extra = stdlib.trim(extra:sub(1, #extra - #time))
                    time = stdlib.trim((time:gsub("^(%d+)(minutes?)", "%1 %2")
                        :gsub("^(%d+)(hours?)", "%1 %2")
                        :gsub("^(%d+)(days?)", "%1 %2")
                        :gsub("^(%d+)(weeks?)", "%1 %2")
                        :gsub("^(%d+)(months?)", "%1 %2")
                        :gsub("^(%d+)(years?)", "%1 %2")))
                end
                local label = "Chapter " .. number
                if extra ~= "" then label = label .. " " .. extra end
                results[#results + 1] = { source_url = url, name = stdlib.trim(label), chapter_number = number,
                    scanlator = "Asura Scans", language = "en", upload_date_text = time or "" }
            end
        end
    end
    return results
end
function M.pages(chapter_url)
    local html, results = http.get(stdlib.url_join(BASE_URL, chapter_url)), {}
    for _, image in ipairs(dom.select(html, "img[data-page-index]")) do
        local src = attr(image, "src") or attr(image, "data-src")
        if src then results[#results + 1] = stdlib.url_join(BASE_URL, src) end
    end
    return results
end
function M.latest()
    return browse({ sort = "latest" })
end
function M.popular()
    return browse({ sort = "popular" })
end
return M
