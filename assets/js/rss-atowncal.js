// Derived from examples on https://github.com/sdepold/vanilla-rss License: MIT
// # Copyright (c) 2020 Shane Curcuru License: Apache 2.0 
const divid = '#rss1'
const rss = new RSS(
  document.querySelector(divid), 
  "https://www.arlingtonma.gov/Home/Components/RssFeeds/RssFeed/View?ctID=6&cateIDs=2", 
  {
    limit: 10,
    ssl: true,
    support: false,
    layoutTemplate: "<ul class='feed-container'>{entries}</ul>",
    entryTemplate: '<li><a href="{url}">{parsedTitle}</a> <small>At: {parsedDate}</small><br/>{bodyPlain} </li>',
    tokens: {
      // Custom to the specific title format used by Calendar-type RSS feeds on website 20200220-sc
      parsedTitle: function(entry, tokens){ return entry.title.substring(0, entry.title.indexOf(' (')) },
      parsedDate: function(entry, tokens){
        let d = moment(entry.title.substring(entry.title.indexOf('(') + 1, entry.title.length - 1), 'MM/DD/YYYY h:mm -      a');
        return d.format("dddd, MMMM Do YYYY, h:mm a")
      }
    }
  }
);

window.onload = function() {
  document.querySelector(divid).innerText = '';
  rss.render();
};
