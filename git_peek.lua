-- default script for clink, called by init.bat when injecting clink

-- !!! THIS FILE IS OVERWRITTEN WHEN CMDER IS UPDATED
-- !!! Use "%CMDER_ROOT%\config\<whatever>.lua" to add your lua startup scripts

-- luacheck: globals clink

-- At first, load the original clink.lua file
-- this is needed as we set the script path to this dir and therefore the original
-- clink.lua is not loaded.
local clink_lua_file = clink.get_env('CMDER_ROOT')..'\\vendor\\clink\\clink.lua'
dofile(clink_lua_file)

-- now add our own things...

---
-- Setting the prompt in clink means that commands which rewrite the prompt do
-- not destroy our own prompt. It also means that started cmds (or batch files
-- which echo) don't get the ugly '{lamb}' shown.
---
local function set_prompt_filter()
    -- get_cwd() is differently encoded than the clink.prompt.value, so everything other than
    -- pure ASCII will get garbled. So try to parse the current directory from the original prompt
    -- and only if that doesn't work, use get_cwd() directly.
    -- The matching relies on the default prompt which ends in X:\PATH\PATH>
    -- (no network path possible here!)
    local old_prompt = clink.prompt.value
    local cwd = old_prompt:match('.*(.:[^>]*)>')
    if cwd == nil then cwd = clink.get_cwd() end

    -- environment systems like pythons virtualenv change the PROMPT and usually
    -- set some variable. But the variables are differently named and we would never
    -- get them all, so try to parse the env name out of the PROMPT.
    -- envs are usually put in round or square parentheses and before the old prompt
    local env = old_prompt:match('.*%(([^%)]+)%).+:')
    -- also check for square brackets
    if env == nil then env = old_prompt:match('.*%[([^%]]+)%].+:') end

    -- build our own prompt
    -- orig: $E[1;32;40m$P$S{git}{hg}$S$_$E[1;30;40m{lamb}$S$E[0m
    -- color codes: "\x1b[1;37;40m"
    local cmder_prompt = "\x1b[1;32;40m{cwd} {git}{hg}{svn} \n\x1b[1;39;40m{lamb} \x1b[0m"
    local lambda
    cmder_prompt = string.gsub(cmder_prompt, "{cwd}", cwd)
    if env == nil then
        lambda = "λ"
    else
        lambda = "("..env..") λ"
    end
    clink.prompt.value = string.gsub(cmder_prompt, "{lamb}", lambda)
end

---
-- Resolves closest directory location for specified directory.
-- Navigates subsequently up one level and tries to find specified directory
-- @param  {string} path    Path to directory will be checked. If not provided
--                          current directory will be used
-- @param  {string} dirname Directory name to search for
-- @return {string} Path to specified directory or nil if such dir not found
local function get_dir_contains(path, dirname)

    -- return parent path for specified entry (either file or directory)
    local function pathname(path)
        local prefix = ""
        local i = path:find("[\\/:][^\\/:]*$")
        if i then
            prefix = path:sub(1, i-1)
        end
        return prefix
    end

    -- Navigates up one level
    local function up_one_level(path)
        if path == nil then path = '.' end
        if path == '.' then path = clink.get_cwd() end
        return pathname(path)
    end

    -- Checks if provided directory contains git directory
    local function has_specified_dir(path, specified_dir)
        if path == nil then path = '.' end
        local found_dirs = clink.find_dirs(path..'/'..specified_dir)
        if #found_dirs > 0 then return true end
        return false
    end

    -- Set default path to current directory
    if path == nil then path = '.' end

    -- If we're already have .git directory here, then return current path
    if has_specified_dir(path, dirname) then
        return path..'/'..dirname
    else
        -- Otherwise go up one level and make a recursive call
        local parent_path = up_one_level(path)
        if parent_path == path then
            return nil
        else
            return get_dir_contains(parent_path, dirname)
        end
    end
end

-- adapted from from clink-completions' git.lua
local function get_git_dir(path)

    -- return parent path for specified entry (either file or directory)
    local function pathname(path)
        local prefix = ""
        local i = path:find("[\\/:][^\\/:]*$")
        if i then
            prefix = path:sub(1, i-1)
        end

        return prefix
    end

    -- Checks if provided directory contains git directory
    local function has_git_dir(dir)
        return clink.is_dir(dir..'/.git') and dir..'/.git'
    end

    local function has_git_file(dir)
        local gitfile = io.open(dir..'/.git')
        if not gitfile then return false end

        local git_dir = gitfile:read():match('gitdir: (.*)')
        gitfile:close()

        return git_dir and dir..'/'..git_dir
    end

    -- Set default path to current directory
    if not path or path == '.' then path = clink.get_cwd() end

    -- Calculate parent path now otherwise we won't be
    -- able to do that inside of logical operator
    local parent_path = pathname(path)

    return has_git_dir(path)
        or has_git_file(path)
        -- Otherwise go up one level and make a recursive call
        or (parent_path ~= path and get_git_dir(parent_path) or nil)
end

local function get_hg_dir(path)
    return get_dir_contains(path, '.hg')
end

local function get_svn_dir(path)
    return get_dir_contains(path, '.svn')
end

---
-- Find out current branch
-- @return {nil|git branch name}
---
local function get_git_branch(git_dir)
    git_dir = git_dir or get_git_dir()

    -- If git directory not found then we're probably outside of repo
    -- or something went wrong. The same is when head_file is nil
    local head_file = git_dir and io.open(git_dir..'/HEAD')
    if not head_file then return end

    local HEAD = head_file:read()
    head_file:close()

    -- if HEAD matches branch expression, then we're on named branch
    -- otherwise it is a detached commit
    local branch_name = HEAD:match('ref: refs/heads/(.+)')

    return branch_name or 'HEAD detached at '..HEAD:sub(1, 7)
end

---
-- Find out current branch
-- @return {false|mercurial branch name}
---
local function get_hg_branch()
    for line in io.popen("hg branch 2>nul"):lines() do
        local m = line:match("(.+)$")
        if m then
            return m
        end
    end

    return false
end

---
-- Find out current branch
-- @return {false|svn branch name}
---
local function get_svn_branch(svn_dir)
    for line in io.popen("svn info 2>nul"):lines() do
        local m = line:match("^Relative URL:")
        if m then
            return line:sub(line:find("/")+1,line:len())
        end
    end

    return false
end

---
-- Get the status of working dir
-- @return {bool}
---
local function get_git_status()
    local file = io.popen("git --no-optional-locks status --porcelain 2>nul")
    for line in file:lines() do
        file:close()
        return false
    end
    file:close()

    return true
end

---
-- Get the status of working dir
-- @return {bool}
---
local function get_hg_status()
    local file = io.popen("hg status -0")
    for line in file:lines() do
        file:close()
        return false
    end
    file:close()

    return true
end

---
-- Get the status of working dir
-- @return {bool}
---
function get_svn_status()
    local file = io.popen("svn status -q")
    for line in file:lines() do
        file:close()
        return false
    end
    file:close()

    return true
end

local function git_prompt_filter()

    -- Colors for git status
    local colors = {
        clean = "\x1b[1;37;40m",
        dirty = "\x1b[31;1m",
    }

    local git_dir = get_git_dir()
    if git_dir then
        -- if we're inside of git repo then try to detect current branch
        local branch = get_git_branch(git_dir)
        local color
        if branch then
            -- Has branch => therefore it is a git folder, now figure out status
            if get_git_status() then
                color = colors.clean
            else
                color = colors.dirty
            end

            clink.prompt.value = string.gsub(clink.prompt.value, "{git}", color.."("..branch..")")
            return false
        end
    end

    -- No git present or not in git file
    clink.prompt.value = string.gsub(clink.prompt.value, "{git}", "")
    return false
end

local function hg_prompt_filter()

    -- Colors for mercurial status
    local colors = {
        clean = "\x1b[1;37;40m",
        dirty = "\x1b[31;1m",
    }

    if get_hg_dir() then
        -- if we're inside of mercurial repo then try to detect current branch
        local branch = get_hg_branch()
        local color
        if branch then
            -- Has branch => therefore it is a mercurial folder, now figure out status
            if get_hg_status() then
                color = colors.clean
            else
                color = colors.dirty
            end

            clink.prompt.value = string.gsub(clink.prompt.value, "{hg}", color.."("..branch..")")
            return false
        end
    end

    -- No mercurial present or not in mercurial file
    clink.prompt.value = string.gsub(clink.prompt.value, "{hg}", "")
    return false
end

local function svn_prompt_filter()
    -- Colors for svn status
    local colors = {
        clean = "\x1b[1;37;40m",
        dirty = "\x1b[31;1m",
    }

    if get_svn_dir() then
        -- if we're inside of svn repo then try to detect current branch
        local branch = get_svn_branch()
        local color
        if branch then
            if get_svn_status() then
                color = colors.clean
            else
                color = colors.dirty
            end

            clink.prompt.value = string.gsub(clink.prompt.value, "{svn}", color.."("..branch..")")
            return false
        end
    end

    -- No mercurial present or not in mercurial file
    clink.prompt.value = string.gsub(clink.prompt.value, "{svn}", "")
    return false
end

---
 -- Get the status of working dir
 -- @return {bool}
---
function get_git_status2()

    local status = {
        anyChanges = false,
        indexAdded = 0,
        indexModified = 0,
        indexDeleted = 0,
        filesAdded = 0,
        filesModified = 0,
        filesDeleted = 0
    }

    for line in io.popen("git -c color.status=false status --short 2>nul"):lines() do
        if line:match("^A(.+)$") then status.indexAdded = status.indexAdded + 1 end
        if line:match("^M(.+)$") then status.indexModified = status.indexModified + 1 end
        if line:match("^R(.+)$") then status.indexModified = status.indexModified + 1 end
        if line:match("^C(.+)$") then status.indexModified = status.indexModified + 1 end
        if line:match("^D(.+)$") then status.indexDeleted = status.indexDeleted + 1 end

        if line:match("^%?(.+)$") then status.filesAdded = status.filesAdded + 1 end
        if line:match("^ A(.+)$") then status.filesAdded = status.filesAdded + 1 end
        if line:match("^ M(.+)$") then status.filesModified = status.filesModified + 1 end
        if line:match("^ R(.+)$") then status.filesModified = status.filesModified + 1 end
        if line:match("^ C(.+)$") then status.filesModified = status.filesModified + 1 end
        if line:match("^ D(.+)$") then status.filesDeleted = status.filesDeleted + 1 end

        status.anyChanges = true
    end

    return status

end

function git_prompt_filter2()

    -- Colors for git status
    local colors = {
        clean = "\x1b[1;37;40m",
        red = "\x1b[31;1m",
        green = "\x1b[32;1m",
		blue = "\x1b[0;34m",
		magenta = "\x1b[0;35m",
    }

    local branch = get_git_branch()
    if branch then
        -- Has branch => therefore it is a git folder, now figure out status

        local status = get_git_status2()

        if not status.anyChanges then
            clink.prompt.value = string.gsub(clink.prompt.value, "{git}", colors.blue..branch)
        else
            -- for k,v in pairs(status) do print(k,v) end
            clink.prompt.value = string.gsub(clink.prompt.value, "{git}", string.format("%s(%s%s%s(*) %s+%d ~%d -%d%s | %s+%d ~%d -%d%s)", 
                colors.clean,
				colors.blue,
				branch,
				colors.red,
                colors.green,
                status.indexAdded,
                status.indexModified,
                status.indexDeleted,
                colors.clean,
                colors.red,
                status.filesAdded,
                status.filesModified,
                status.filesDeleted,
                colors.clean))
        end

        return true
    end

    -- No git present or not in git file
    clink.prompt.value = string.gsub(clink.prompt.value, "{git}", "")
    return false
end

-- insert the set_prompt at the very beginning so that it runs first
clink.prompt.register_filter(set_prompt_filter, 1)
clink.prompt.register_filter(hg_prompt_filter, 50)
-- clink.prompt.register_filter(git_prompt_filter, 50)
clink.prompt.register_filter(git_prompt_filter2, 50)
clink.prompt.register_filter(svn_prompt_filter, 50)

local completions_dir = clink.get_env('CMDER_ROOT')..'/vendor/clink-completions/'
for _,lua_module in ipairs(clink.find_files(completions_dir..'*.lua')) do
    -- Skip files that starts with _. This could be useful if some files should be ignored
    if not string.match(lua_module, '^_.*') then
        local filename = completions_dir..lua_module
        -- use dofile instead of require because require caches loaded modules
        -- so config reloading using Alt-Q won't reload updated modules.
        dofile(filename)
    end
end
