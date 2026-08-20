local M = {}
local BASE_URL = "https://weebcentral.com"

local function first(html, selector) return dom.select(html, selector)[1] end
local function attr(element, name) return element and element.attributes and element.attributes[name] end
local function clean(text)
    text = text or ""
    for _ = 1, 2 do
        text = text:gsub("&amp;", "&")
            :gsub("&#039;", "'")
            :gsub("&#39;", "'")
            :gsub("&apos;", "'")
            :gsub("&quot;", '"')
            :gsub("&lt;", "<")
            :gsub("&gt;", ">")
    end
    return stdlib.trim((text:gsub("%s+", " "):gsub("%s+,", ",")))
end
local function text_only(html)
    return clean((html or ""):gsub("<br%s*/?>", " "):gsub("<[^>]->", " "))
end
local function detail_value(html, label)
    local block = html:match("<strong>%s*" .. label .. "%s*:?%s*</strong>(.-)</li>")
    return text_only(block)
end
local function absolute(url) return stdlib.url_join(BASE_URL, url or "") end
local function surrounding_article(html, needle)
    local start_at = html:find(needle, 1, true)
    if not start_at then return "" end
    local before = html:sub(1, start_at)
    local article_start = before:match(".*()<article")
    local article_end = html:find("</article>", start_at, true)
    if not article_start or not article_end then return "" end
    return html:sub(article_start, article_end + 9)
end
local function infer_card_type(title, block)
    title = title or ""
    block = block or ""
    if block:find("[Ee]pisode%s*[%d%.]+") then return "manhwa" end
    local lower = title:lower()
    if lower:find("martial peak", 1, true)
        or lower:find("apotheosis", 1, true)
        or lower:find("magic emperor", 1, true)
        or lower:find("nano machine", 1, true)
        or lower:find("tales of demons and gods", 1, true)
        or lower:find("log into the future", 1, true) then
        return "manhua"
    end
    if lower:find("solo leveling", 1, true)
        or lower:find("academy", 1, true)
        or lower:find("max-level", 1, true)
        or lower:find("lookism", 1, true)
        or lower:find("schooled", 1, true)
        or lower:find("pick me up", 1, true)
        or lower:find("infinite mage", 1, true)
        or lower:find("reality quest", 1, true)
        or lower:find("eleceed", 1, true)
        or lower:find("novel's extra", 1, true)
        or lower:find("iron-blooded hound", 1, true)
        or lower:find("swordmaster", 1, true)
        or lower:find("overgeared", 1, true)
        or lower:find("deadbeat noble", 1, true) then
        return "manhwa"
    end
    return "manga"
end
local function headers()
    return { ["User-Agent"] = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36" }
end
local function form_headers()
    local values = headers()
    values["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8"
    return values
end
local function get(url) return http.get(url, headers()) end

local function card_results(html)
    local results, seen, covers, cover_titles = {}, {}, {}, {}
    for _, image in ipairs(dom.select(html, 'img[src*="/cover/fallback/"]')) do
        local src = attr(image, "src")
        local id = src and src:match("/cover/fallback/([^%.]+)%.")
        if id and not covers[id] then
            covers[id] = absolute(src)
            cover_titles[id] = clean((attr(image, "alt") or ""):gsub("%s+[Cc]over$", ""))
        end
    end
    for _, link in ipairs(dom.select(html, 'a[href*="/series/"]')) do
        local href = attr(link, "href")
        local id = href and href:match("/series/([^/]+)/[^/?#]+")
        local title = clean(link.text)
        if title == "" and id then title = cover_titles[id] or "" end
        title = clean((title:gsub("%s+[Cc]over$", "")))
        local url = href and absolute(href)
        if url and id and title ~= "" and not seen[url] then
            local block = surrounding_article(html, href) ~= "" and surrounding_article(html, href) or surrounding_article(html, title)
            local content_type = infer_card_type(title, block)
            local cover = covers[id] or ("https://temp.compsci88.com/cover/fallback/" .. id .. ".jpg")
            seen[url] = true
            results[#results + 1] = {
                title = title,
                manga_title = title,
                url = url,
                manga_url = url,
                thumbnail_url = cover,
                type = content_type,
                sourceType = content_type,
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
    local html = http.post and http.post(BASE_URL .. "/search/simple?location=main", http.encode({ text = query }), form_headers())
        or get(BASE_URL .. "/search?" .. http.encode({ text = query }))
    return card_results(html)
end

function M.manga_details(url)
    url = absolute(url)
    local html = get(url)
    local title = first(html, "h1") or first(html, 'meta[property="og:title"]')
    local image = first(html, 'meta[property="og:image"]')
    local meta_description = first(html, 'meta[name="description"]') or first(html, 'meta[property="og:description"]')
    local canonical = first(html, 'link[rel="canonical"]')
    local genres = {}
    for _, genre in ipairs(dom.select(html, 'a[href*="/genres/"], a[href*="/search?included_tag"]')) do
        local value = clean(genre.text)
        if value ~= "" then genres[#genres + 1] = value end
    end
    local description = text_only(html:match("<strong>%s*Description%s*</strong>%s*<p[^>]*>(.-)</p>") or "")
    if description == "" then description = clean(meta_description and attr(meta_description, "content") or "") end
    local author = detail_value(html, "Author%(s%)")
    local content_type = detail_value(html, "Type")
    local status = detail_value(html, "Status")
    local released = detail_value(html, "Released")
    return {
        title = clean((title and (title.text or attr(title, "content")) or ""):gsub("|%s*Weeb Central$", "")),
        url = canonical and absolute(attr(canonical, "href")) or url,
        description = description,
        genres_json = json.encode(genres),
        author = author,
        artist = author,
        type = content_type,
        status = status,
        released = released,
        thumbnail_url = absolute(image and attr(image, "content") or ""),
        source = "Weeb Central",
        language = "en"
    }
end

function M.chapters(manga_url)
    manga_url = absolute(manga_url)
    local series_id = manga_url:match("/series/([^/]+)")
    local html = ""
    if series_id then
        local ok, full_html = pcall(get, BASE_URL .. "/series/" .. series_id .. "/full-chapter-list")
        if ok and full_html ~= "" then html = full_html end
    end
    if html == "" then html = get(manga_url) end
    local results, seen = {}, {}
    for _, link in ipairs(dom.select(html, 'a[href*="/chapters/"]')) do
        local href = attr(link, "href")
        if href then
            local url = absolute(href)
            if not seen[url] and not url:find("/bookmarks", 1, true) and not url:find("/report", 1, true) then
                seen[url] = true
                local escaped_href = href:gsub("([^%w])", "%%%1")
                local block = html:match('href="' .. escaped_href .. '".-</a>') or ""
                local text = clean(link.text)
                if text == "" then
                    text = clean((block:match("([Cc]hapter%s*[%d%.]+)") or ""))
                end
                local date = block:match('datetime="([^"]+)"') or ""
                local number = text:match("[Cc]hapter%s*([%d%.]+)") or text:match("[Ee]pisode%s*([%d%.]+)")
                results[#results + 1] = {
                    source_url = url,
                    name = text ~= "" and text or "Chapter",
                    chapter_number = number,
                    upload_date_text = date,
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
    local html = get(BASE_URL .. "/latest-updates/1")
    local ok, next_page = pcall(get, BASE_URL .. "/latest-updates/2")
    if ok then html = html .. next_page end
    return card_results(html)
end

function M.popular()
    return card_results(get(BASE_URL .. "/hot-updates"))
end

return M
