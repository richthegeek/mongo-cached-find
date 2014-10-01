// Generated by CoffeeScript 1.7.1
(function() {
  var CachedFind, EventEmitter, HashMap, MongoOplog, Promise, getWatcher, sift, watchers,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  sift = require('sift');

  MongoOplog = require('mongo-oplog');

  Promise = require('bluebird');

  HashMap = require('hashmap').HashMap;

  EventEmitter = require('events').EventEmitter;

  watchers = {};

  getWatcher = function(collection) {
    var address, host, port;
    host = collection.db.serverConfig._state.master.host;
    port = collection.db.serverConfig._state.master.port;
    address = collection.db.options.url.replace(/\/[^\/]+$/, '/local');
    if (!watchers[address]) {
      watchers[address] = new Promise(function(resolve, reject) {
        var watcher;
        watcher = MongoOplog(address);
        return watcher.tail(function() {
          return resolve(watcher);
        });
      });
    }
    return watchers[address];
  };

  module.exports = CachedFind = (function(_super) {
    __extends(CachedFind, _super);

    function CachedFind(collection, query) {
      var ns;
      this.collection = collection;
      this.query = query;
      ns = collection.db.databaseName + '.' + collection.collectionName;
      this.sifter = sift(query);
      this.documents = new HashMap();
      this.refresh();
      this.watcher = getWatcher(collection);
      this.watcher.then((function(_this) {
        return function(watcher) {
          _this.emit('tailing', watcher);
          watcher.on('insert', function(event) {
            if (event.ns === ns) {
              if (_this.check(event.o)) {
                return _this.add(event.o);
              }
            }
          });
          watcher.on('update', function(event) {
            if (event.ns === ns) {
              if (_this.check(event.o)) {
                return _this.add(event.o);
              } else {
                return _this.remove(event.o._id);
              }
            }
          });
          return watcher.on('remove', function(event) {
            if (event.ns === ns) {
              return _this.remove(event.o._id);
            }
          });
        };
      })(this));
    }

    CachedFind.prototype.refresh = function(callback) {
      return this.query = new Promise((function(_this) {
        return function(resolve, reject) {
          _this.documents.clear();
          return _this.collection.find(_this.query).each(function(err, row) {
            if (err) {
              _this.emit('error', err);
              return reject(err);
            } else if (row) {
              return _this.documents.set(row._id, row);
            } else {
              _this.emit('init', _this.documents.values());
              return resolve();
            }
          });
        };
      })(this));
    };

    CachedFind.prototype.check = function(document) {
      return this.sifter.test(document);
    };

    CachedFind.prototype.add = function(document) {
      this.documents.set(document._id, document);
      return this.emit('add', document);
    };

    CachedFind.prototype.remove = function(id) {
      if (this.documents[id]) {
        this.documents.remove(id);
        return this.emit('remove', id);
      }
    };

    CachedFind.prototype.get = function(cb) {
      var bad, good;
      good = (function(_this) {
        return function() {
          return cb(null, _this.documents.values());
        };
      })(this);
      bad = function(reason) {
        return cb(reason);
      };
      return this.query.then(good, bad);
    };

    return CachedFind;

  })(EventEmitter);

}).call(this);
