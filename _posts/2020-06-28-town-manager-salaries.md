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

With the recent [news article on our Town Manager's personal move](https://yourarlington.com/arlington-archives/town-school/town-news/town-hall/17412-manager-062820.html) to another town, people have been discussing how the Town Manager is compensated and other matters about the organization of responsibilities at the top of our town hall.  Thinking about how much compensation the Select Board wrote into the Town Manager's contract got me to thinking - what would be an appropriate salary?

Town Managers in places as dense as Arlington do a **lot**.  Our Town Manager has five bosses - each of the Select Board members.  The Town Manager is also responsible for a $151 million annual budget, with hundreds of employees in town governance.  That's the equivalent of a mid-sized corporation, plus the added complexity of state and local bylaws prescribing how many operations have to run.  I figured the best way to get a sense of appropriate compensation is to look at what comparable towns pay their managers (or mayors).

## Town Manager Base Salaries - Estimated

IN PROGRESS...

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

## Notes On Data Sources

Importantly, note that the above figures are **estimates** for **base salary** only.  Many towns don't make it simple to find executive salaries, so some figures come from news sources that are a few years old.  The numbers above are also only base salary - they don't include other compensation, benefits, or other allowances like housing offsets or official town cars to drive.  Similarly, figures may come from 2020, 2019, or in a few cases earlier. 

- Town expenses come from [state-reported Schedule A Expenditures](https://dlsgateway.dor.state.ma.us/reports/rdPage.aspx?rdReport=ScheduleA.GenFund_MAIN) from 2019
- Population comes from [US Census Bureau Population Estimates Program](https://www.census.gov/data/tables/time-series/demo/popest/2010s-total-cities-and-towns.html), 2019 population estimates.
- Town Manager / Mayor base salaries come from either actual FY2020 proposed budgets from the municipality, or come from these news articles all in the past 6 years. 

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
const policePerCapita = [ // Figures rounded
  ['Municipality', 'Police $ Per Capita'],
  ['North Andover', '164'],
  ['Stoneham', '175'],
  ['Melrose', '178'],
  ['Arlington', '180'],
  ['Needham', '211'],
  ['Winchester', '212'],
  ['Natick', '223'],
  ['Reading', '238'],
  ['Medford', '241'],
  ['Milton', '264'],
  ['Belmont', '268'],
  ['Watertown', '271'],
  ['Brookline', '283']
]
const policePercent = [
  ['Municipality', 'Police Budget %'],
  ['Needham', '0.0428'],
  ['Winchester', '0.0441'],
  ['North Andover', '0.0536'],
  ['Arlington', '0.0542'],
  ['Natick', '0.0554'],
  ['Melrose', '0.0573'],
  ['Stoneham', '0.0617'],
  ['Brookline', '0.0623'],
  ['Reading', '0.0627'],
  ['Belmont', '0.0717'],
  ['Watertown', '0.0746'],
  ['Milton', '0.0786'],
  ['Medford', '0.0870']
]
c3.generate({
  bindto: '#tmpercapita',
  data: {
    x: 'Municipality',
    rows: policePerCapita,
    type: 'bar',
    colors: {
      Arlington: '#008000'
    },
    labels: {
      format: {
        'Police $ Per Capita': d3.format('$')
      }
    }
  },
  grid: {
    y: {
      lines: [
        {
          value: 180,
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
  bindto: '#ppercent',
  data: {
    x: 'Municipality',
    rows: policePercent,
    type: 'bar',
    labels: {
      format: {
        'Police Budget %': d3.format('.2%')
      }
    }
  },
  grid: {
    y: {
      lines: [
        {
          value: 0.0542,
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
