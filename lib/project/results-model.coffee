Q = require 'q'
{_} = require 'atom'
{Emitter} = require 'emissary'

class Result
  @create: (result) ->
    if result? and result.matches?.length then new Result(result) else null

  constructor: (result) ->
    _.extend(this, result)

module.exports =
class ResultsModel
  Emitter.includeInto(this)

  constructor: (state={}) ->
    @useRegex = state.useRegex ? false
    @caseSensitive = state.caseSensitive ? false

    atom.project.eachEditor (editSession) =>
      editSession.on 'contents-modified', => @onContentsModified(editSession)

    @clear()

  serialize: ->
    {@useRegex, @caseSensitive}

  clear: ->
    @clearSearchState()
    @clearReplacementState()
    @emit('cleared', @getResultsSummary())

  clearSearchState: ->
    @pathCount = 0
    @matchCount = 0
    @regex = null
    @results = {}
    @paths = []
    @active = false
    @pattern = ''
    @emit('search-state-cleared', @getResultsSummary())

  clearReplacementState: ->
    @replacementPattern = null
    @replacedPathCount = null
    @replacementCount = null
    @emit('replacement-state-cleared', @getResultsSummary())

  search: (pattern, searchPaths, replacementPattern, {onlyRunIfChanged, keepReplacementState}={}) ->
    return Q() if onlyRunIfChanged and pattern? and searchPaths? and pattern == @pattern and _.isEqual(searchPaths, @searchedPaths)

    if keepReplacementState
      @clearSearchState()
    else
      @clear()

    @active = true
    @regex = @getRegex(pattern)
    @pattern = pattern
    @searchedPaths = searchPaths

    @updateReplacementPattern(replacementPattern)

    onPathsSearched = (numberOfPathsSearched) =>
      @emit('paths-searched', numberOfPathsSearched)

    promise = atom.project.scan @regex, {paths: searchPaths, onPathsSearched}, (result) =>
      @setResult(result.filePath, Result.create(result))

    @emit('search', promise)
    promise.then => @emit('finished-searching', @getResultsSummary())

  replace: (pattern, searchPaths, replacementPattern, replacementPaths) ->
    regex = @getRegex(pattern)

    @updateReplacementPattern(replacementPattern)

    @replacedPathCount = 0
    @replacementCount = 0

    promise = atom.project.replace regex, replacementPattern, replacementPaths, (result) =>
      if result and result.replacements
        @replacedPathCount++
        @replacementCount += result.replacements
      @emit('path-replaced', result)

    @emit('replace', promise)
    promise.then =>
      @emit('finished-replacing', @getResultsSummary())
      @search(pattern, searchPaths, replacementPattern, {keepReplacementState: true})

  updateReplacementPattern: (replacementPattern) ->
    @replacementPattern = replacementPattern or null
    @emit('replacement-pattern-changed', @regex, replacementPattern)

  toggleUseRegex: ->
    @useRegex = not @useRegex

  toggleCaseSensitive: ->
    @caseSensitive = not @caseSensitive

  getResultsSummary: ->
    pattern = @pattern or ''
    {
      pattern
      @pathCount
      @matchCount
      @replacementPattern
      @replacedPathCount
      @replacementCount
    }

  getPathCount: ->
    @pathCount

  getMatchCount: ->
    @matchCount

  getPattern: ->
    @pattern or ''

  getPaths: ->
    @paths

  getResult: (filePath) ->
    @results[filePath]

  setResult: (filePath, result) ->
    if result
      @addResult(filePath, result)
    else
      @removeResult(filePath)

  addResult: (filePath, result) ->
    if @results[filePath]
      @matchCount -= @results[filePath].matches.length
    else
      @pathCount++
      @paths.push(filePath)

    @matchCount += result.matches.length

    @results[filePath] = result
    @emit('result-added', filePath, result)

  removeResult: (filePath) ->
    if @results[filePath]
      @pathCount--
      @matchCount -= @results[filePath].matches.length

      @paths = _.without(@paths, filePath)
      delete @results[filePath]
      @emit('result-removed', filePath)

  getRegex: (pattern) ->
    flags = 'g'
    flags += 'i' unless @caseSensitive

    if @useRegex
      new RegExp(pattern, flags)
    else
      new RegExp(_.escapeRegExp(pattern), flags)

  onContentsModified: (editSession) =>
    return unless @active

    matches = []
    editSession.scan @regex, (match) ->
      matches.push(match)

    result = Result.create({matches})
    @setResult(editSession.getPath(), result)
    @emit('finished-searching', @getResultsSummary())
