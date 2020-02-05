---
title: "Covering Key Town Issues"
excerpt: "Brief listing of various town issues I'm tracking"
permalink: /issues/
layout: default
header:
  overlay_image: /assets/images/delfi-de-la-rua-152121-h.jpg
  caption: "Photo: [**Delfi de la Rua / Unsplash**](https://unsplash.com)"
---

{% for post in site.issues %}
  {% unless post.exclude %}
    {% include archive-single.html %}
  {% endunless %}
{% endfor %}