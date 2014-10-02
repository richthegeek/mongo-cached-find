sift = require 'sift'
MongoOplog = require 'mongo-oplog'
Promise = require 'bluebird'
HashMap = require('hashmap').HashMap
EventEmitter = require('events').EventEmitter

class CachedFind extends EventEmitter

	constructor: (@collection, @query = {}) ->
		ns = getNamespace collection

		@sifter = sift query
		@documents = new HashMap()

		@refresh()

		@watcher = getWatcher(collection)
		@watcher.then (watcher) =>
			@emit 'tailing', watcher

			@refresh()

			watcher.on 'insert', (event) =>
				if event.ns is ns
					if @check event.o
						@add event.o
			
			watcher.on 'update', (event) =>
				if event.ns is ns
					if @check event.o
						@add event.o
					else
						@remove event.o._id

			watcher.on 'remove', (event) =>
				if event.ns is ns
					@remove event.o._id

	refresh: (callback) ->
		@pendingQuery = new Promise (resolve, reject) =>
			@collection.find(@query).toArray (err, rows) =>
				if err
					@emit 'error', err
					callback? err
					reject err

				else
					@documents.clear()
					for row in rows
						@documents.set row._id, row

					@emit 'init', rows
					callback? null, rows
					resolve()

	check: (document) ->
		@sifter.test document

	add: (document) ->
		@documents.set document._id, document
		@emit 'add', document

	remove: (id) ->
		if @documents[id]
			@documents.remove id
			@emit 'remove', id

	get: (cb) ->
		good = => cb null, @documents.values()
		bad = (reason) -> cb reason

		@pendingQuery.then good, bad

getNamespace = (collection) ->
	return collection.db.databaseName + '.' + collection.collectionName

getServerAddress = (collection) ->
	host = collection.db.serverConfig.host
	port = collection.db.serverConfig.port
	address = "mongodb://#{host}:#{port}"

getWatcher = (collection) ->
	address = getServerAddress(collection) + '/local'
	if not module.exports.watchers[address]
		module.exports.watchers[address] = new Promise (resolve, reject) ->
			watcher = MongoOplog address
			watcher.tail ->
				resolve watcher

	return module.exports.watchers[address]

module.exports = (collection, query) ->
	address = getServerAddress collection
	ns = getNamespace collection
	key = JSON.stringify {address, ns, query}

	if not module.exports.caches.has key
		console.log 'NEW CF', ns, query
		module.exports.caches.set key, new CachedFind collection, query
	
	return module.exports.caches.get key

module.exports.watchers = new HashMap()
module.exports.caches = new HashMap()
