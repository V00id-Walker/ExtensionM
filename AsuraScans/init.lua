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
local function paired_cards(html, link_selector, image_selector)
    local results, links, images = {}, dom.select(html, link_selector), dom.select(html, image_selector)
    for index, link in ipairs(links) do
        local image, href = images[index], attr(link, "href")
        local title = attr(image, "alt") or ""
        if href and title ~= "" then results[#results + 1] = {
            title = title, manga_title = title,
            url = stdlib.url_join(BASE_URL, href), manga_url = stdlib.url_join(BASE_URL, href),
            thumbnail_url = stdlib.url_join(BASE_URL, attr(image, "src") or attr(image, "data-src") or ""),
        } end
    end
    return results
end
function M.search(params)
    params = params or {}
    local query = { search = params.query or params.title, author = params.author, status = params.status,
        type = params.type, order = params.order or "update", page = params.page or 1 }
    local html = http.get(BASE_URL .. "/browse/comics?" .. http.encode(query))
    return paired_cards(html, '[data-series-id] > a[href*="/comics/"]', '[data-series-id] > a[href*="/comics/"] img')
end
function M.manga_details(url)
    url = stdlib.url_join(BASE_URL, url)
    local html, genres = http.get(url), {}
    for _, el in ipairs(dom.select(html, 'a[href*="genres="]')) do genres[#genres + 1] = stdlib.trim(el.text or "") end
    local function text(selector) local el = first(html, selector); return el and stdlib.trim(el.text or "") or "" end
    local image, canonical = first(html, 'meta[property="og:image"]'), first(html, 'link[rel="canonical"]')
    return { title = text("h1"), url = canonical and stdlib.url_join(BASE_URL, attr(canonical, "href")) or url,
        author = text('a[href*="author="]'), artist = text('a[href*="artist="]'),
        description = text("#description-text"), genres_json = json.encode(genres),
        status = text('a[href*="status="]'):lower(), thumbnail_url = image and stdlib.url_join(BASE_URL, attr(image, "content")) or "",
        type = text('a[href*="type="]'):lower() }
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
                local label = (link.text or ""):match("Chapter[^\n]*") or "Chapter " .. number
                results[#results + 1] = { source_url = url, name = stdlib.trim(label), chapter_number = number,
                    scanlator = "Asura Scans", language = "en" }
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
    local html = http.get(BASE_URL .. "/comics")
    local results, seen = {}, {}
    for href, cover, title in html:gmatch('<a href="([^"]+)" class="col%-span%-4[^"]*">%s*<img src="([^"]+)" alt="([^"]+)"') do
        local url = stdlib.url_join(BASE_URL, href)
        if not seen[url] then
            seen[url] = true
            title = stdlib.decode_entities(title)
            results[#results + 1] = { title = title, manga_title = title, url = url, manga_url = url,
                thumbnail_url = stdlib.url_join(BASE_URL, cover) }
        end
    end
    return results
end
function M.popular()
    local html = http.get(BASE_URL .. "/browse/comics?order=popular")
    return paired_cards(html, '[data-series-id] > a[href*="/comics/"]', '[data-series-id] > a[href*="/comics/"] img')
end
return M
