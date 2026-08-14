local M = {}
function M.search() return {} end
function M.manga_details(url) return { title = "", url = url or "", genres_json = "[]" } end
function M.chapters() return {} end
function M.pages() return {} end
function M.latest() return {} end
function M.popular() return {} end
return M
