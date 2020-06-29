---
title: "Comparing Town Manager Salaries"
excerpt: "Comparing Arlington's town manager compensation to nearby comparable towns."
toc: false
author_profile: false
classes: wide
categories:
  - TownHall
tags:
  - Data
  - Finances
header:
  overlay_image: /assets/images/finances.jpg
  caption: "Photo: [**NORTHFOLK / Unsplash**](https://unsplash.com/)"
---

With the recent [news article on our Town Manager's personal move](https://yourarlington.com/arlington-archives/town-school/town-news/town-hall/17412-manager-062820.html) to another town, people have been discussing how the Town Manager is compensated and other matters about the organization of responsibilities at the top of our town hall.  Thinking about how much compensation the Select Board wrote into the Town Manager's contract got me to thinking - what _would_ be an appropriate salary?

Town Managers in places as dense as Arlington do a **lot**.  Our Town Manager has five bosses - each of the five Select Board members.  The Arlington Town Manager is also responsible for a $151 million annual budget, with over 350+ employees in town governance (**not** including School staff).  That's the equivalent of a mid-sized corporation, plus the added complexity of state and local bylaws prescribing how many operations have to run.  I figured the best way to get a sense of appropriate compensation is to look at what comparable towns pay their managers (or mayors).

## Town Manager Base Salaries - APPROXIMATE

In terms of just _base_ salary, Arlington seems to fall in the middle of the comparable towns/cities I was able to find data for easily - **when measuring base salary versus** the budget or population of the town.  Simple comparisons of manager salaries are not valuable, since different towns have different needs and scopes of work.  Another useful visualization would be manager salary versus number town employees, but employee FTE data is buried in various reports differently in different towns and would take a lot more work to record accurately.

<figure class="half">
  <div class='chartfigure'>
    <h3 style='text-align: center;'>Town Manager Salary Per Capita</h3>
    <div id="tmpercapita"></div>
  </div>
  <div class='chartfigure'>
    <h3 style='text-align: center;'>Town Manager Salary as %age of Total Budget</h3>
    <div id="tmpercent"></div>
  </div>
</figure>

As a reminder: if you think the Town Manager's compensation is off, then remember that it's [set by contract](https://yourarlington.com/arlington-archives/town-school/town-news/transportation/14856-bus-091318), and the [Select Board is the group that signs off on the terms](/townhall/#board-of-selectmen).

## Notes On Data Sources

Importantly, note that the above figures are **estimates** for **base salary** only.  It's not easy to find executive salaries in some towns, so some figures come from news sources that are a year or more old.  The numbers above are also only base salary - they don't include other compensation, benefits, or other allowances like housing offsets or official town cars to drive, which may be significant.  While some municipalities provide car allowances to mayors, Arlington provides a significant housing allowance, as well as various other benefits.  Similarly, figures may come from 2020, 2019, or in a few cases earlier. 

- Town expenses come from [state-reported Schedule A Expenditures](https://dlsgateway.dor.state.ma.us/reports/rdPage.aspx?rdReport=ScheduleA.GenFund_MAIN) from 2019
- Population comes from [US Census Bureau Population Estimates Program](https://www.census.gov/data/tables/time-series/demo/popest/2010s-total-cities-and-towns.html), 2019 population estimates.
- Town Manager / Mayor base salaries come from either actual FY2020 proposed budgets from the municipality, or come from news articles listed below.
- Arlington's Town Manager base salary can be seen in the [Finance Committee Report to Town Meeting 2020](https://www.arlingtonma.gov/home/showdocument?id=51585), page 29.
- Arlington's Town Manager total compensation (including benefits, housing, etc. totaling just under $50K) is in the [Arlington Open Checkbook's](https://www.arlingtonma.gov/town-governance/financial-budget-information/open-checkbook) [Excel download of 2018 Salary Report](https://www.arlingtonma.gov/Home/ShowDocument?id=45529).
- Arlington's town employee FTE number (which does not include Schools) from 2018 is in the [Comprehensive Annual Financial Report](https://www.arlingtonma.gov/home/showdocument?id=45803), page 143.

Corrections - with links to source documents! - appreciated so I can update this comparison. 

### Town Manager Compensation News Coverage

- [Eagle Tribune article 2020](https://www.eagletribune.com/news/merrimack_valley/north-andover-town-manager-contract-extended-through-2021/article_a3b1ecd0-686e-5297-b557-a3db8ddbfefa.html): "In lieu of the car, the updated contract provides [North Andover town manager] for a $10,000 salary increase to $180,177"
- [PIBuzz blog](https://pibuzz.com/government-employees/massachusetts-public-salaries/) has links to Needham salary spreadsheet noting the FY2015 Needham's Town Manager salary: $180,455.
- [WickedLocal Winchester wrote in 2017](https://winchester.wickedlocal.com/news/20170109/report-winchesters-highest-paid-employees): "Town Manager Richard Howard, who took in $169,899.33 in total compensation for FY16..."
- [Patch](https://patch.com/massachusetts/watertown/watertown-town-manager-gets-23k-raise) notes the Winchester town manager: "Driscoll, who previously earned $172,500, was given a salary of $184,000 in FY17 and $195,500 in FY18"
- The [City of Melrose bylaws](https://ecode360.com/15358467#15358468) site notes: "Effective January 1, 2014, the salary for the position of Mayor shall be §$125,000 per annum."
- An [article in HomeNewsHere](http://homenewshere.com/stoneham_independent/news/article_12ea9102-f9dd-11e6-b1a4-d335fbb8b912.html) discusses how Stoneham's Select Board set "...'incentive-based' goals for Town Administrator Thomas Younger, whose annual salary rate now hinges upon his ability to reach five milestones during his first year as Stoneham’s CEO."
- [Boston.com reviewed pay levels for many city mayors](https://www.boston.com/uncategorized/noprimarytagmatch/2013/02/06/mayors-pay-raises-a-thorny-issue-for-local-cities) in 2013.


<!-- Load d3/c3 resources and styles -->
<style>
.gridGreen line {
  stroke: #00ff00 !important;
  color: #00ff00 !important;
}
</style>
<link href="/assets/css/c3.css" rel="stylesheet">
<script src="/assets/js/d3.min.js" charset="utf-8"></script>
<script src="/assets/js/c3.min.js"></script>
<script>
// Hack: static data copied from calculated .csv files
const towns = [
  'Arlington',
  'Belmont',
  'Brookline',
  'Medford',
  'Melrose',
  'Milton',
  'Natick',
  'Needham',
  'North Andover',
  'Reading',
  'Stoneham',
  'Watertown',
  'Winchester'
]
const municipality = 'Municipality'
const salaryPerCapita = 'Manager Salary Per Capita'
const salaryPercent = 'Manager Salary Budget %'
const arlPerCapita = '4.59'
const arlPercent = '0.00138'
const tmPerCapita = [ // Figures rounded
  [municipality, salaryPerCapita],
  ['Medford', '2.38'],
  ['Brookline', '3.5'],
  ['Melrose', '4.46'],
  ['Natick', '4.58'],
  ['Arlington', arlPerCapita],
  ['Watertown', '5.44'],
  ['Needham', '5.75'],
  ['North Andover', '5.78'],
  ['Belmont', '6.69'],
  ['Reading', '7.36'],
  ['Winchester', '7.45']
]
const tmPercent = [
  [municipality, salaryPercent],
  ['Brookline', '0.00077'],
  ['Medford', '0.00086'],
  ['Natick', '0.00113'],
  ['Needham', '0.00117'],
  ['Arlington', arlPercent],
  ['Melrose', '0.00144'],
  ['Watertown', '0.0015'],
  ['Winchester', '0.00155'],
  ['Belmont', '0.00179'],
  ['North Andover', '0.00189'],
  ['Reading', '0.00194']
]
c3.generate({
  bindto: '#tmpercapita',
  data: {
    x: municipality,
    rows: tmPerCapita,
    type: 'bar',
    colors: {
      Arlington: '#008000'
    },
    labels: {
      format: {
        salaryPerCapita: d3.format('$')
      }
    }
  },
  grid: {
    y: {
      lines: [
        {
          value: Number(arlPerCapita),
          class: 'gridGreen',
          text: ''
        }
      ]
    }
  },
  axis: {
    rotated: true,
    x: {
      type: 'category',
      categories: towns,
      tick: {
        centered: true
      }
    },
    y: {
      show: false
    }
  }
})
c3.generate({
  bindto: '#tmpercent',
  data: {
    x: municipality,
    rows: tmPercent,
    type: 'bar',
    labels: {
      format: {
        salaryPercent: d3.format('.2%')
      }
    }
  },
  grid: {
    y: {
      lines: [
        {
          value: Number(arlPercent),
          class: 'gridGreen',
          text: ''
        }
      ]
    }
  },
  axis: {
    rotated: true,
    x: {
      type: 'category',
      categories: towns,
      tick: {
        centered: true
      }
    },
    y: {
      show: false,
      label: {
        text: '% of Total Expense'
      }
    }
  }
})
</script>
