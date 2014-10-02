# mongo-cached-find

This module allows you to specify a Mongo "find" query and keep its results up to date with the contents of the database, by using the oplog.

This is useful when you are storing some configuration documents which are read frequently and must not be stale.

## Usage

```js
CachedFind = require('mongo-cached-find')

settings = CachedFind(db.collection('settings'), {})
settings.get(function(err, documents) {
  ...
})
```

This will then set up a tailer on the oplog which will keep the list of settings documents up to date without actually querying the collection each time `settings.get` is called.

You can listen to various events on `settings` to know when things have changed:

```js
settings.on('init', function(documents) {}) // called when the documents are retrieved initially

settings.on('error', function(err) {}) // receives the same error as settings.get does

settings.on('add', function(document) {}) // emitted with each document as it is added to the set

settings.on('remove', function(document) {}) // emitted with a document as it is removed from the set

settings.on('tail', function(watcher) {}) // emitted when the oplog is tailing

```

## Parameters
`new CachedFind( MongoDB.Collection collection, Object query, Boolean refresh_after_tail = true )`

* The collection should have the host and port available via `collection.db.serverConfig.host/port`
* The query is a standard query object, nothing special here.
* The refresh_after_tail (default true) changes when the initial fetch occurs. In some cases the oplog tailing can take several seconds to start, with no guarantee that the database hasn't changed in the interim. This option, when false, could potentially allow some data to be stale in exchange for the initial get returning much sooner.

## Caveats
1. This uses the [Sift.JS](https://github.com/crcn/sift.js) library for checking if tailed documents match the query, so whilst it is pretty good it may fail on particularly complicated queries.
2. There is no way, currently, to close the tailer. Whilst there will only be one tailer for Mongo host (shared amongst all CachedFind instances on that host) this may still be a memory issue. Technically you can call `CachedFind::watcher.stop()` but this will stop ALL instances on that host.
3. The watcher does not filter and emits to all CachedFinds which then check if the namespace is correct. Whilst this is a fairly lightweight operation in and of itself, it hasn't been tested on a massively heavy site.
