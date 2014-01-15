cheerio = require('cheerio')

exports.updateSongLinks = (output, userkey, cb) ->
    # Parse data with cheerio
    doc = cheerio.load(output)
    elems = []
    doc("span").each (i, elem) ->
        if elem.attribs? && elem.attribs.title?
            elems.push(elem)
    iter = _.partial(updateSongElem, userkey)
    async.reduce elems, doc, iter, (err, doc) ->
        cb(doc.html())

