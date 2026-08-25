local M = {}
local BASE_URL = "https://anikototv.to"

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
            :gsub("&nbsp;", " ")
    end
    return stdlib.trim((text:gsub("<[^>]->", " "):gsub("%s+", " ")))
end
local function absolute(url) return stdlib.url_join(BASE_URL, url or "") end
local function headers()
    return {
        ["Referer"] = BASE_URL .. "/"
    }
end
local function ajax_headers()
    local values = headers()
    values["X-Requested-With"] = "XMLHttpRequest"
    return values
end
local function get(url) return http.get(url, headers()) end
local function ajax(url) return http.get(url, ajax_headers()) end

local function json_result(raw)
    local ok, data = pcall(json.parse, raw or "")
    if not ok or not data then return nil end
    return data
end

local function meta_value(html, label)
    local value = html:match(label .. ":%s*<span>(.-)</span>")
    return clean(value or "")
end

local function add_card(results, seen, href, title, cover, rating, format, episodes)
    title = clean(title)
    local url = absolute(href or "")
    url = url:gsub("/ep%-[^/?#]+", "")
    if title == "" or url == "" or seen[url] then return end
    seen[url] = true
    results[#results + 1] = {
        title = title,
        manga_title = title,
        url = url,
        manga_url = url,
        thumbnail_url = absolute(cover or ""),
        rating = clean(rating or ""),
        format = clean(format or ""),
        episode_count = tonumber(episodes or ""),
        type = "anime",
        content_type = "anime",
        sourceType = "anime",
        source = "AniKoto",
        language = "en"
    }
end

local function cards_from_search_html(html)
    local results, seen = {}, {}
    for block in (html or ""):gmatch('<a class="item".-</a>') do
        local href = block:match('href="([^"]-/watch/[^"]+)"') or block:match('href="([^"]+)"')
        local cover = block:match('<img[^>]-src="([^"]+)"')
        local title = block:match('class="name[^"]*"[^>]*>(.-)</div>')
        local rating = block:match('class="dot rating"[^>]*>(.-)</span>')
        local format = block:match('</i>%s*[%d%.]+%s*</span>%s*<span class="dot">(.-)</span>') or block:match('<span class="dot">(TV.-)</span>')
        add_card(results, seen, href, title, cover, rating, format)
    end
    return results
end

local function cards_from_page(html, limit)
    local results, seen = {}, {}
    limit = limit or 24
    for block in (html or ""):gmatch('<div class="item[^"]*">%s*<div class="inner">(.-)<div class="genre">') do
        local href = block:match('<a class="name[^"]*" href="([^"]+)"') or block:match('<a href="([^"]-/watch/[^"]+)"')
        local cover = block:match('<img[^>]-src="([^"]+)"')
        local title = block:match('<a class="name[^"]*"[^>]*>(.-)</a>') or block:match('<img[^>]-alt="([^"]+)"')
        local rating = block:match('<div class="m%-item rated">%s*<span>(.-)</span>') or block:match('class="rating"[^>]*>(.-)</i>')
        local format = block:match('<div class="right">(.-)</div>') or block:match('<label>([^<]-)</label>')
        local episodes = block:match('class="ep%-status total"[^>]*>%s*<span>%s*(%d+)')
            or block:match('<div class="m%-item">%s*<span>%s*(%d+)')
        add_card(results, seen, href, title, cover, rating, format, episodes)
        if #results >= limit then return results end
    end
    if #results == 0 then
        for _, link in ipairs(dom.select(html, 'a[href*="/watch/"]')) do
            local href = attr(link, "href")
            local title = clean(attr(link, "title") or link.text)
            if title ~= "" and not title:match("^%d[%d%s]*%a*$") then add_card(results, seen, href, title, "", "", "", nil) end
            if #results >= limit then return results end
        end
    end
    return results
end

function M.search(params)
    params = params or {}
    local query = params.query or params.title or ""
    local raw = ajax(BASE_URL .. "/ajax/anime/search?" .. http.encode({ keyword = query }))
    local data = json_result(raw)
    if data and data.result and data.result.html then
        local rows = cards_from_search_html(data.result.html)
        if #rows > 0 then return rows end
    end
    return cards_from_page(get(BASE_URL .. "/filter?" .. http.encode({ keyword = query })), 24)
end

local function watch_id(url, html)
    return (html or ""):match('id="watch%-main"[^>]-data%-id="(%d+)"')
        or tostring(url or ""):match("/watch/[^/?#]+%?id=(%d+)")
end

function M.manga_details(url)
    url = absolute(url)
    local html = get(url)
    local genres = {}
    for _, genre in ipairs(dom.select(html, 'a[href*="/genre/"]')) do
        local value = clean(genre.text)
        if value ~= "" then genres[#genres + 1] = value end
    end
    local title = clean((first(html, "h1") or {}).text or "")
    local image = first(html, 'meta[property="og:image"]')
    local description = clean(html:match('<div class="synopsis.-<div class="content">(.-)</div>') or "")
    if description == "" then
        local meta = first(html, 'meta[name="description"]') or first(html, 'meta[property="og:description"]')
        description = clean(meta and attr(meta, "content") or "")
    end
    return {
        title = title,
        url = url,
        description = description,
        genres_json = json.encode(genres),
        status = meta_value(html, "Status"):lower(),
        format = meta_value(html, "Type"),
        type = "anime",
        content_type = "anime",
        episode_count = tonumber(meta_value(html, "Episodes"):match("%d+") or ""),
        rating = clean((html:match('<i class="rating">(.-)</i>') or meta_value(html, "MAL"))),
        studios = meta_value(html, "Studios"),
        producers = meta_value(html, "Producers"),
        thumbnail_url = absolute(image and attr(image, "content") or ""),
        anime = json.encode({ id = watch_id(url, html), base_url = BASE_URL }),
        source = "AniKoto",
        language = "en"
    }
end

function M.chapters(anime_url)
    anime_url = absolute(anime_url)
    local html = get(anime_url)
    local id = watch_id(anime_url, html)
    if not id then return {} end
    local data = json_result(ajax(BASE_URL .. "/ajax/episode/list/" .. id))
    local episode_html = data and data.result or ""
    local results, seen = {}, {}
    for block in tostring(episode_html):gmatch("<a [^>]-data%-id=\"%d+\".-</a>") do
        local ep_id = block:match('data%-id="([^"]+)"')
        local number = block:match('data%-num="([^"]+)"') or block:match('data%-slug="([^"]+)"')
        local slug = block:match('data%-slug="([^"]+)"') or number
        local ids = block:match('data%-ids="([^"]+)"')
        local title = block:match('title="([^"]+)"')
        local timestamp = block:match('data%-timestamp="([^"]+)"')
        if number and ids and not seen[number] then
            seen[number] = true
            results[#results + 1] = {
                source_url = anime_url .. "/ep-" .. tostring(slug or number) .. "?anime_id=" .. id .. "&episode_id=" .. tostring(ep_id or "") .. "&servers=" .. ids,
                episode_url = anime_url .. "/ep-" .. tostring(slug or number) .. "?anime_id=" .. id .. "&episode_id=" .. tostring(ep_id or "") .. "&servers=" .. ids,
                name = clean(title or ("Episode " .. tostring(number))),
                title = clean(title or ("Episode " .. tostring(number))),
                episode_number = number,
                episode_sort_key = tonumber(number),
                upload_date = tonumber(timestamp),
                language = "en",
                type = "anime",
                content_type = "anime"
            }
        end
    end
    return results
end

local function streams_from_server_html(html)
    local results = {}
    for type_block in tostring(html):gmatch('<div class="type" data%-type="[^"]+".-</div>') do
        local audio = type_block:match('data%-type="([^"]+)"') or ""
        for li in type_block:gmatch("<li [^>]-data%-link%-id=\"[^\"]+\"[^>]*>.-</li>") do
            local link_id = li:match('data%-link%-id="([^"]+)"')
            local server = clean(li:match(">(.-)</li>") or "")
            if link_id then
                local data = json_result(ajax(BASE_URL .. "/ajax/server?get=" .. link_id))
                local result = data and data.result or {}
                local embed = result.url
                if embed and embed ~= "" then
                    results[#results + 1] = {
                        url = embed,
                        server = server ~= "" and server or "AniKoto",
                        quality = server,
                        audio = audio,
                        is_hls = embed:find("%.m3u8", 1, true) ~= nil,
                        headers = {
                            ["Referer"] = BASE_URL .. "/"
                        }
                    }
                end
            end
        end
    end
    return results
end

function M.pages(episode_url)
    local servers = tostring(episode_url or ""):match("[?&]servers=([^&#]+)")
    if not servers then
        local series_url = tostring(episode_url or ""):gsub("/ep%-[^/?#]+.*$", "")
        local wanted = tostring(episode_url or ""):match("/ep%-([^/?#]+)")
        for _, episode in ipairs(M.chapters(series_url)) do
            if tostring(episode.episode_number) == tostring(wanted) or tostring(episode.source_url):find("/ep%-" .. tostring(wanted), 1, false) then
                servers = tostring(episode.source_url):match("[?&]servers=([^&#]+)")
                break
            end
        end
    end
    if not servers then return {} end
    local data = json_result(ajax(BASE_URL .. "/ajax/server/list?" .. http.encode({ servers = servers })))
    return streams_from_server_html(data and data.result or "")
end

function M.latest()
    return cards_from_page(get(BASE_URL .. "/latest-updated"), 24)
end

function M.popular()
    return cards_from_page(get(BASE_URL .. "/most-viewed"), 24)
end

return M
