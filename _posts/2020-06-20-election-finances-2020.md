---
title: "Election Finances in 2020"
excerpt: "Tabulating all major candidate election expenses."
toc: false
author_profile: false
classes: wide
categories:
  - Elections
tags:
  - Data
  - TownHall
header:
  overlay_image: /assets/images/voted.jpg
  caption: "Photo: [**Element 5 Digital / Unsplash**](https://unsplash.com/@element5digital)"
---

Besides all the excitement of this year's delayed town election with primarily mail-in ballots, and the many competitive races, the [town is now doing a recount of several races](https://yourarlington.com/arlington-archives/town-school/elections/17379-recount-061920.html).  Some candidates were elected by very slim margins - fewer than 100 votes difference of thousands of ballots in the preliminary count.  Several candidates have requested recounts of their races, which the [town clerk will be performing in the next few days](https://www.arlingtonma.gov/Home/Components/News/News/10294/).

Looking at the election results got me to thinking about campaign finances.  Yes, there are [campaign finance reports, even for town offices in MA](https://www.ocpf.us/Legal/CampaignFinanceLaw)!  Every major position candidate (but not Town Meeting members) in Arlington files a basic report of expenditures and receipts by the 8th day preceeding the election, and the [town clerk posts them on the elections website](https://www.arlingtonma.gov/town-governance/elections-voting/2020-election-results).  The average receipts for candidate's campaigns this year was over $5,000, with one candidate fundraising more than $10,000!

With several newcomers being elected to major town boards, do you think that differences in campaign spending had a material impact on the race, or the [immense numbers of letters to the editor](https://yourarlington.com/easyblog.html)?  Or are any comparisons with past year's elections just plain silly due to COVID-19 restrictions and all the discussion about ballot request postcards?

## Town Election Finances - 2020

<table class="table">
  {% for row in site.data.electionfinance2020 %}
    {% if forloop.first %}
    <tr>
      {% for pair in row %}
        <th>{{ pair[0] }}</th>
      {% endfor %}
    </tr>
    {% endif %}

    {% tablerow pair in row %}
      {{ pair[1] }}
    {% endtablerow %}
  {% endfor %}
</table>

All data is manually transcribed from the [Town Clerk's posted Campaign Finance Reports](https://www.arlingtonma.gov/town-governance/elections-voting/2020-election-results), and a [spreadsheet of this data](https://github.com/ShaneCurcuru/menotomymatters/blob/master/_data/electionfinance2020.csv) is available.  Factual corrections appreciated.

## Massachusetts Campaign Laws

For those interested in learning more about elections and recounts, see:

- [Town election page](https://arlingtonma.gov/elections)
- [MA Secretary of State page](https://www.sec.state.ma.us/ele/eleidx.htm) - with many guides on ballots, where to vote, citizen petitions, and more.
- [MA campaign finance laws](https://www.mass.gov/law-library/970-cmr)
- [Overview of recount laws in MA](https://ballotpedia.org/Recount_laws_in_Massachusetts)
- [MA detailed guide to how recounts are performed](https://www.sec.state.ma.us/ele/elepdf/Election-Recounts.pdf)