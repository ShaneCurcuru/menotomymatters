---
title: "Arlington Police Spending Comparison"
excerpt: "Comparing Arlington's Police budget to nearby comparable towns."
toc: false
author_profile: false
classes: wide
categories:
  - Police
tags:
  - Data
  - Finances
header:
  overlay_image: /assets/images/finances.jpg
  caption: "Photo: [**NORTHFOLK / Unsplash**](https://unsplash.com/)"
---

As the national discussion around systemic racism and police reform turns into local activism about our own Arlington police department, it helps to figure out exactly how town government and local policing actually work so as to come up with the most **effective** strategies for change.

The variety of issues people are calling to address range from defunding police budgets; to requiring training or certifications; to specific policy or individual personnel changes in the department; or to changing the whole model of policing into other public safety and services organizations.  While a few of these issues we can work on locally, changes in many areas will require larger changes with [police unions](https://www.vox.com/policy-and-politics/21290981/police-union-contracts-minneapolis-reform) and [state legislation](https://digboston.com/why-massachusetts-cops-arent-featured-in-the-usa-today-misconduct-database/).  These are all complex issues that are unlikely to change in response to simple protests or publicity, no matter how important or obvious the changes may seem to be.

## Police Spending

One _slightly_ simpler issue to consider is funding: our town has a budget, and you can [see where the town spends our tax dollars](http://arlingtonvisualbudget.org/), and you can see the [police department's achievements and detailed budget requests](https://www.arlingtonma.gov/home/showdocument?id=46072).  Fundamentally, one of the ways we shape how our town government operates is through the budget: how much funding to different departments get for what expenses?  But even that is a complex question, given that many municipal salaries are determined by union contracts, and that reading budgets is hard work.

Another way to look at police funding is to compare how Arlington does compared to other nearby towns.  The Town Manager has a regular set of nearby towns and cities that are comparable - in a general sense - to our town.  So how does Arlington compare with police spending versus Belmont or Watertown?

## Police Spending Per Capita

When we compare Arlington's spending on police to comparable towns, we do well, coming in at the bottom third of towns!  Our annual police spending is about $180 per capita, lower than most towns, and only coming in higher than North Reading, Stoneham, and Melrose.  If we consider the police budget as a percentage of a total town budget, the police also come in the bottom third, aat 5.42% of the budget, about the same as North Andover and Natick, and the only notably lower towns are Needham and Winchester.

<figure class="half">
  <div class='chartfigure'>
    <h3 style='text-align: center;'>Police Budget Per Capita (2019)</h3>
    <div id="ppercapita"></div>
  </div>
  <div class='chartfigure'>
    <h3 style='text-align: center;'>Police Budget As %age Of Total Budget (2019)</h3>
    <div id="ppercent"></div>
  </div>
</figure>

## Open Data For Arlington

These charts come from a new open data project I'm working on with a handful of Arlingtonians.  Much like I've tried to bring transparency with how town government works in my Meeting Trackers, several other folks are working with me to showcase more open data about town finances and statistics, in the same vein as the [Arlington Visual Budget](http://arlingtonvisualbudget.org/).  Stay tuned for more open data about our town!

## Notes On Data Sources

There is one caveat for these charts, which are derived from the [MA Division of Local Services](https://www.mass.gov/orgs/division-of-local-services) reported [budgets by state defined category](https://dlsgateway.dor.state.ma.us/reports/rdPage.aspx?rdReport=ScheduleA.GenFund_MAIN).  Different towns report a few expenses in different categories: for example one town will pay crossing guard salaries from Police budgets; another town will pay crossing guards in the School budget.  On the whole, those accounting differences are reasonably small, so as a planning metric, these are still useful comparisons.

You can [download this data as a CSV spreadsheet](https://arlingtonma.info/data/finance/GenFundExpenditures2019-comps.csv), see it's [open data metadata](https://arlingtonma.info/data/finance/GenFundExpenditures2019-comps.json), or find the [original source data on mass.gov](https://dlsgateway.dor.state.ma.us/reports/rdPage.aspx?rdReport=ScheduleA.GenFund_MAIN) as reported using standard classifications [from the MA Department of Revenue](https://www.mass.gov/orgs/division-of-local-services).  Population figures come from the [US Census Bureau Population Estimates Program](https://www.census.gov/data/tables/time-series/demo/popest/2010s-total-cities-and-towns.html), 2019 population estimates.

**Comparable towns** to Arlington (Belmont, Brookline, Medford, Melrose, Milton, Natick, Needham, North Andover, Reading, Stoneham, Watertown, Winchester) are defined in the [Town Manager's Annual Reports](https://www.arlingtonma.gov/departments/town-manager/town-manager-s-annual-budget-financial-report).


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
  bindto: '#ppercapita',
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
