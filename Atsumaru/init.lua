local M = {}
local BASE_URL = "https://atsu.moe"
local CDN_URL = "https://cdn.atsu.moe"

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
local function asset(url)
    url = url or ""
    if url == "" then return "" end
    if url:find("^https?://") then return url end
    if url:sub(1, 1) ~= "/" then url = "/static/" .. url end
    return stdlib.url_join(CDN_URL, url)
end
local function normalize_type(value)
    value = clean(value or "")
    local lower = value:lower()
    if lower == "manwha" or lower == "manhwa" then return "manhwa" end
    if lower == "manhua" then return "manhua" end
    if lower == "manga" then return "manga" end
    return ""
end

local function manga_url(id) return BASE_URL .. "/manga/" .. tostring(id or "") end

local function add_item(results, seen, item)
    if not item or item.isAdult == true then return end
    if item.medium and item.medium ~= "Comic" then return end
    local id = item.id
    local title = clean(item.title or item.englishTitle or item.name or "")
    if not id or title == "" then return end
    local url = manga_url(id)
    if seen[url] then return end
    seen[url] = true
    local cover = asset(item.mediumImage or item.posterMedium or item.smallImage or item.posterSmall or item.image or item.poster)
    local kind = normalize_type(item.type)
    if kind == "" then return end
    results[#results + 1] = {
        title = title,
        manga_title = title,
        url = url,
        manga_url = url,
        thumbnail_url = cover,
        status = item.status,
        type = kind,
        sourceType = kind,
        source = "Atsumaru",
        language = "en"
    }
end

local function items_results(raw)
    local ok, data = pcall(json.parse, raw)
    if not ok or not data then return {} end
    local rows = data.items or data.data or data
    local results, seen = {}, {}
    for _, item in ipairs(rows) do add_item(results, seen, item) end
    return results
end

local function search_results(raw)
    local ok, data = pcall(json.parse, raw)
    if not ok or not data then return {} end
    local results, seen = {}, {}
    for _, hit in ipairs(data.hits or {}) do add_item(results, seen, hit.document) end
    return results
end

local function explore_query(params)
    params = params or {}
    local query = clean(params.query or params.title or "")
    local sort = params.sort or params.order or "recently_updated"
    return http.encode({
        q = query ~= "" and query ~= "*" and query or "*",
        query_by = "title,englishTitle,otherNames,authors,acronyms",
        query_by_weights = "4,3,2,1,1",
        num_typos = query ~= "" and query ~= "*" and "4,3,2,1,0" or "0,0,0,0,0",
        prefix = "true,true,true,true,false",
        include_fields = "id,title,englishTitle,poster,posterSmall,posterMedium,type,medium,isAdult,status,year,mbRating,popularity,dateAdded",
        filter_by = "hidden:!=true && isAdult:=false",
        sort_by = (sort == "popular" or sort == "views" or sort == "most_viewed") and "popularity:desc" or "dateAdded:desc",
        page = params.page or 1,
        per_page = params.per_page or 20,
        infix = "off,off,fallback,off,off"
    })
end

function M.search(params)
    params = params or {}
    return search_results(get(BASE_URL .. "/collections/manga/documents/search?" .. explore_query(params)))
end

local function page_data(manga_id)
    local html = get(manga_url(manga_id))
    local raw = html:match("window%.mangaPage%s*=%s*(.-)%s*</script>")
    if raw and not raw:find("PREFETCHED_MANGA_PAGE", 1, true) then
        raw = raw:gsub(";%s*$", "")
        local ok, data = pcall(json.parse, raw)
        if ok and data then return data end
    end
    local api_raw = get(BASE_URL .. "/api/manga/page?" .. http.encode({ id = manga_id }))
    local ok, data = pcall(json.parse, api_raw)
    return ok and data or nil
end

local function all_chapters_data(manga_id)
    local raw = get(BASE_URL .. "/api/manga/allChapters?" .. http.encode({ mangaId = manga_id }))
    local ok, data = pcall(json.parse, raw)
    return ok and data or nil
end

local function scanlator_names(page)
    local names = {}
    for _, scanlator in ipairs((page or {}).scanlators or {}) do
        if scanlator.id and scanlator.name then
            names[tostring(scanlator.id)] = clean(scanlator.name)
        end
    end
    return names
end

function M.manga_details(url)
    local id = tostring(url or ""):match("/manga/([^/?#]+)") or tostring(url or "")
    local data = page_data(id)
    local page = data and data.mangaPage or {}
    local genres = {}
    for _, genre in ipairs(page.genres or {}) do
        if genre.name then genres[#genres + 1] = genre.name end
    end
    local authors = page.authors or {}
    return {
        title = clean(page.title or ""),
        url = manga_url(page.id or id),
        author = authors[1] and authors[1].name or "",
        artist = authors[2] and authors[2].name or "",
        description = clean(page.synopsis or ""),
        genres_json = json.encode(genres),
        status = clean(page.status or ""):lower(),
        thumbnail_url = asset(page.poster and (page.poster.mediumImage or page.poster.image) or page.mediumImage or page.image),
        type = normalize_type(page.type),
        source = "Atsumaru",
        language = "en"
    }
end

function M.chapters(manga_url_value)
    local id = tostring(manga_url_value or ""):match("/manga/([^/?#]+)") or tostring(manga_url_value or "")
    local page = page_data(id)
    local scanlators = scanlator_names(page and page.mangaPage)
    local data = all_chapters_data(id) or page
    local chapters = data and (data.chapters or (data.mangaPage and data.mangaPage.chapters)) or {}
    local results = {}
    for _, chapter in ipairs(chapters) do
        if chapter.id then
            local scanlator_id = chapter.scanlationMangaId or chapter.scanlatorId or chapter.scanId
            local scanlator = scanlator_id and scanlators[tostring(scanlator_id)] or clean(chapter.scanlator or chapter.scanlationProvider or "")
            results[#results + 1] = {
                source_url = manga_url(id) .. "?chapter=" .. chapter.id,
                name = clean(chapter.title or ("Chapter " .. tostring(chapter.number or ""))),
                chapter_number = chapter.number,
                chapter_sort_key = chapter.index,
                scanlator = scanlator ~= "" and scanlator or nil,
                upload_date = chapter.createdAt,
                page_count = chapter.pageCount,
                language = "en"
            }
        end
    end
    return results
end

function M.pages(chapter_url)
    local manga_id = tostring(chapter_url or ""):match("/manga/([^/?#]+)")
    local chapter_id = tostring(chapter_url or ""):match("[?&]chapter=([^&#]+)") or tostring(chapter_url or ""):match("/chapter/([^/?#]+)")
    if not manga_id or not chapter_id then return {} end
    local raw = get(BASE_URL .. "/api/read/chapter?" .. http.encode({ mangaId = manga_id, chapterId = chapter_id }))
    local ok, data = pcall(json.parse, raw)
    if not ok or not data or not data.readChapter then return {} end
    local results = {}
    for _, page in ipairs(data.readChapter.pages or {}) do
        if page.image then results[#results + 1] = asset(page.image) end
    end
    return results
end

function M.latest()
    return items_results(get(BASE_URL .. "/api/home2/recentlyUpdated?" .. http.encode({ offset = 0, limit = 20 })))
end

function M.popular()
    return items_results(get(BASE_URL .. "/api/home2/popular?" .. http.encode({ offset = 0, limit = 20 })))
end

return M
