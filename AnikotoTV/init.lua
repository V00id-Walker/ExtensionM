local M = {}
local BASE_URL = "https://anikototv.to"

local function first(html, selector)
    return dom.select(html, selector)[1]
end

local function attr(element, name)
    return element and element.attributes and element.attributes[name]
end

local function clean(text)
    return stdlib.trim(((text or ""):gsub("&amp;", "&"):gsub("&#039;", "'"):gsub("&quot;", '"'):gsub("%s+", " ")))
end

local function absolute(url)
    return stdlib.url_join(BASE_URL, url or "")
end

local function series_url(url)
    local full = absolute(url)
    return (full:gsub("/ep%-%d+.*$", ""))
end

local function poster_results(html)
    local results, seen = {}, {}
    for _, title in ipairs(dom.select(html, ".ani.poster .name.d-title, .poster .name.d-title")) do
        local href = attr(title, "href")
        if not href then
            local parent = title.parent
            href = attr(parent, "href")
        end
        if href then
            local url = series_url(href)
            if not seen[url] then
                local card = title.parent
                local image = card and dom.select(card, "img")[1] or nil
                seen[url] = true
                results[#results + 1] = {
                    title = clean(title.text),
                    manga_title = clean(title.text),
                    url = url,
                    manga_url = url,
                    thumbnail_url = absolute(attr(image, "data-src") or attr(image, "src") or ""),
                    type = "anime",
                    source = "AniKoto TV",
                    language = "en"
                }
            end
        end
    end
    return results
end

function M.search(params)
    params = params or {}
    local query = params.query or params.title or ""
    local page = params.page or 1
    local html = http.get(BASE_URL .. "/filter?" .. http.encode({ keyword = query, page = page }))
    return poster_results(html)
end

function M.manga_details(url)
    url = series_url(url)
    local html = http.get(url)
    local title = first(html, "h1, .detail .name, .info .name, .d-title")
    local image = first(html, "meta[property='og:image']") or first(html, ".poster img, .cover img")
    local description = first(html, ".description, .desc, .synopsis, .content")
    local genres = {}
    for _, genre in ipairs(dom.select(html, 'a[href*="/genre/"]')) do
        local value = clean(genre.text)
        if value ~= "" then genres[#genres + 1] = value end
    end
    local plain = clean((html:gsub("<[^>]->", " ")))
    return {
        title = clean(title and title.text or ""),
        url = url,
        description = clean(description and description.text or ""),
        genres_json = json.encode(genres),
        thumbnail_url = absolute(attr(image, "content") or attr(image, "data-src") or attr(image, "src") or ""),
        status = plain:match("Status%s+([%a%s%-]+)%s+"),
        format = plain:match("Type%s+([%a%s%-_]+)%s+"),
        season = plain:match("Season%s+([%a%s]+)%s+"),
        year = plain:match("Premiered%s+%a+%s+(%d%d%d%d)") or plain:match("Date aired%s+.-(%d%d%d%d)"),
        episodes = plain:match("Episodes%s+(%d+)"),
        language = "en",
        type = "anime",
        source = "AniKoto TV"
    }
end

function M.chapters(manga_url)
    manga_url = series_url(manga_url)
    local html = http.get(manga_url)
    local results, seen = {}, {}
    for _, link in ipairs(dom.select(html, 'a[href*="/ep-"]')) do
        local href = attr(link, "href")
        if href then
            local url = absolute(href)
            if not seen[url] then
                seen[url] = true
                local number = href:match("/ep%-(%d+)")
                local label = clean(link.text)
                if label == "" and number then label = "Episode " .. number end
                results[#results + 1] = {
                    source_url = url,
                    name = label,
                    episode_number = number,
                    episode_sort_key = number and tonumber(number) or nil,
                    language = "en",
                    type = "anime"
                }
            end
        end
    end
    return results
end

function M.pages(episode_url)
    local html = http.get(absolute(episode_url))
    local streams, seen = {}, {}
    for url in html:gmatch('https?://[^"\']+%.m3u8[^"\']*') do
        if not seen[url] then
            seen[url] = true
            streams[#streams + 1] = { url = url, quality = "auto", server = "AniKoto", is_hls = true }
        end
    end
    for _, source in ipairs(dom.select(html, "source[src]")) do
        local url = absolute(attr(source, "src"))
        if url ~= "" and not seen[url] then
            seen[url] = true
            streams[#streams + 1] = {
                url = url,
                quality = attr(source, "size") or attr(source, "res") or attr(source, "label") or "auto",
                server = "AniKoto",
                is_hls = url:find(".m3u8", 1, true) ~= nil
            }
        end
    end
    return streams
end

function M.latest()
    return poster_results(http.get(BASE_URL .. "/latest-updated"))
end

function M.popular()
    return poster_results(http.get(BASE_URL .. "/most-viewed"))
end

function M.genres()
    local html, results, seen = http.get(BASE_URL .. "/home"), {}, {}
    for _, link in ipairs(dom.select(html, 'a[href*="/genre/"]')) do
        local name = clean(link.text)
        if name ~= "" and not seen[name] then
            seen[name] = true
            results[#results + 1] = name
        end
    end
    return results
end

function M.by_genre(args)
    local genre = args[1] or ""
    local page = args[2] or 1
    return poster_results(http.get(BASE_URL .. "/genre/" .. genre .. "?page=" .. page))
end

return M
