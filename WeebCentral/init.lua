local M = {}
local BASE_URL = "https://weebcentral.com"

local function first(html, selector) return dom.select(html, selector)[1] end
local function attr(element, name) return element and element.attributes and element.attributes[name] end
local function clean(text)
    return stdlib.trim(((text or ""):gsub("&amp;", "&"):gsub("&#039;", "'"):gsub("&quot;", '"'):gsub("%s+", " ")))
end
local function absolute(url) return stdlib.url_join(BASE_URL, url or "") end
local function headers()
    return { ["User-Agent"] = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36" }
end
local function get(url) return http.get(url, headers()) end

local function card_results(html)
    local results, seen = {}, {}
    for _, link in ipairs(dom.select(html, 'a[href*="/series/"]')) do
        local href = attr(link, "href")
        local title = clean(link.text)
        title = clean((title:gsub("%s+[Cc]over$", "")))
        local url = href and absolute(href)
        if url and title ~= "" and not seen[url] then
            seen[url] = true
            results[#results + 1] = {
                title = title,
                manga_title = title,
                url = url,
                manga_url = url,
                thumbnail_url = "",
                source = "Weeb Central",
                language = "en"
            }
        end
    end
    return results
end

function M.search(params)
    params = params or {}
    local query = params.query or params.title or ""
    local html = http.post and http.post(BASE_URL .. "/search/simple?location=main", http.encode({ text = query }), headers())
        or get(BASE_URL .. "/search?" .. http.encode({ text = query }))
    return card_results(html)
end

function M.manga_details(url)
    url = absolute(url)
    local html = get(url)
    local title = first(html, "h1") or first(html, 'meta[property="og:title"]')
    local image = first(html, 'meta[property="og:image"]')
    local description = first(html, 'meta[name="description"]') or first(html, 'meta[property="og:description"]')
    local canonical = first(html, 'link[rel="canonical"]')
    local genres = {}
    for _, genre in ipairs(dom.select(html, 'a[href*="/genres/"], a[href*="/search?included_tag"]')) do
        local value = clean(genre.text)
        if value ~= "" then genres[#genres + 1] = value end
    end
    local plain = clean(html:gsub("<[^>]->", " "))
    return {
        title = clean((title and (title.text or attr(title, "content")) or ""):gsub("|%s*Weeb Central$", "")),
        url = canonical and absolute(attr(canonical, "href")) or url,
        description = clean(description and attr(description, "content") or ""),
        genres_json = json.encode(genres),
        status = clean(plain:match("Status%s+([%a%s%-_]+)%s+") or ""),
        thumbnail_url = absolute(image and attr(image, "content") or ""),
        source = "Weeb Central",
        language = "en"
    }
end

function M.chapters(manga_url)
    manga_url = absolute(manga_url)
    local html = get(manga_url)
    local results, seen = {}, {}
    for _, link in ipairs(dom.select(html, 'a[href*="/chapters/"]')) do
        local href = attr(link, "href")
        if href then
            local url = absolute(href)
            if not seen[url] and not url:find("/bookmarks", 1, true) and not url:find("/report", 1, true) then
                seen[url] = true
                local text = clean(link.text)
                local number = text:match("[Cc]hapter%s*([%d%.]+)") or text:match("[Ee]pisode%s*([%d%.]+)")
                results[#results + 1] = {
                    source_url = url,
                    name = text ~= "" and text or "Chapter",
                    chapter_number = number,
                    language = "en"
                }
            end
        end
    end
    return results
end

function M.pages(chapter_url)
    local url = absolute(chapter_url)
    local html = get(url .. "/images?is_prev=False")
    if html == "" then html = get(url) end
    local results, seen = {}, {}
    for _, image in ipairs(dom.select(html, "#chapter-images img, main img")) do
        local src = attr(image, "src") or attr(image, "data-src")
        if src and not src:find("broken_image", 1, true) then
            local page = absolute(src)
            if not seen[page] then seen[page] = true; results[#results + 1] = page end
        end
    end
    return results
end

function M.latest()
    return card_results(get(BASE_URL .. "/"))
end

function M.popular()
    return card_results(get(BASE_URL .. "/hot-updates"))
end

return M
