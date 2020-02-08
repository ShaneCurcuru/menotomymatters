---
title: "Covering Key Town Issues"
excerpt: "Brief listing of various town issues I'm tracking"
permalink: /issues/
layout: archive
header:
  overlay_image: /assets/images/issues.jpg
  caption: "Photo: [**Delfi de la Rua / Unsplash**](https://unsplash.com)"
---

{% for post in site.issues %}
  {% unless post.exclude %}
    {% include archive-single.html %}
  {% endunless %}
{% endfor %}