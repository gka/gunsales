
# if you don't have `needs` get it using
# install.packages('needs')
# library(needs)
needs(seasonal, ggplot2, data.table, zoo, x13binary, stringr, dplyr)

source('src/functions.R')
source('src/plot.R')

debug <- TRUE

# load data
alldata <- read.csv("data/ncis_bystate_bymonth_bytype.csv", na = "#N/A", stringsAsFactors=FALSE)

## estimate gun sales using formula by Jurgen Brauer, published here
## http://www.smallarmssurvey.org/fileadmin/docs/F-Working-papers/SAS-WP14-US-Firearms-Industry.pdf

## note: the column `multiple_corrected` is a copy of `multiple` in which
## we set the checks in the "multiple" category to 0 for California
alldata <- alldata %>% mutate(guns_sold=(handgun + longgun) * 1.1 + multiple_corrected * 2)

## let's look at the total numbers; state_ts() is a helper function
total <- alldata %>% state_ts('Totals', 'guns_sold')

## compute seasonally adjusted gun sales (using final() and seas() from seasonal)
totalSeas <- total %>% seas %>% final

## create a new data frame that eventually stores all the
## data we need in the final piece
out_data <- ts_to_dataframe(total, 'guns_total') %>% 
    mutate(guns_total=round(guns_total, 0))

## expand the data.frame, adding more volumns
out_data <- data.frame(out_data, guns_total_seas=round(as.matrix(totalSeas),0))

if (debug) {
    print(head(out_data))
    print(tail(out_data))
}

## create a temporary matrix for computing the
## handgun_share and longgun_share columns
## cbind works correctly here as it operates on timeseries object
tmp <- cbind(final(seas(state_ts(alldata, 'Totals', 'handgun'))),
             final(seas(state_ts(alldata, 'Totals', 'longgun'))),
             final(seas(state_ts(alldata, 'Totals', 'other'))),
             final(seas(state_ts(alldata, 'Totals', 'multiple_corrected'))))
colnames(tmp) <- c('handgun', 'longgun', 'other', 'multiple')
out_data <- data.frame(out_data, tmp)

## convert NAs to 0 in column other
out_data$other[is.na(out_data$other)] <- 0

## compute the handgun/longgun share
out_data <- within(out_data, {
    handgun_share=round(handgun / (handgun+longgun+other+multiple*0.5), 4)
    longgun_share=round(longgun / (handgun+longgun+other+multiple*0.5), 4)
    })

## plot percent of national for selected states 
show_states <- c('New Jersey', 'Maryland', 'Georgia',
                 'Louisiana', 'Mississippi', 'Missouri')

for (s in show_states) {
    s.ts <- state_data(alldata, s, total, totalSeas)

    ## merge with out_data
    temp <- mutate(ts_to_dataframe(s.ts), value=round(value,3))
    colnames(temp) <- c('year', 'month', str_replace_all(str_to_lower(s), ' ', '_'))
    out_data <- data.frame(out_data, temp[,3,drop=FALSE])
}
if (debug) {
    print(head(out_data))
    print(tail(out_data))
}

## compute handgun sales for DC: handung * 1.1 + multiple
dchandgun_checks <- state_ts(alldata, 'District of Columbia', 'handgun', outer_zeros_to_na=F)
dcmultiple <- state_ts(alldata, 'District of Columbia', 'multiple', outer_zeros_to_na=F)
dchandgun <- (dchandgun_checks * 1.1 + dcmultiple + 1) %>% seas %>% final - 1
totalHandgun <- (state_ts(alldata, 'Totals', 'handgun') * 1.1 +
                  state_ts(alldata, 'Totals', 'multiple')) %>% seas %>% final
dchandgunPct <- dchandgun / totalHandgun * 100000

## merge with out_data
temp <- ts_to_dataframe(round(dchandgunPct, 1), 'dc_handguns_per_100k_national_sales')
out_data <- data.frame(out_data, temp[,3,drop=FALSE])

## estimate how much more guns are sold missouri after law change
missouri <- state_data(alldata, 'Missouri', normalize = F, adj_seasonal = F)
missouri.avg_pre_2007 <- mean(missouri[73:84])
missouri.avg_post_2008 <- mean(missouri[97:108])
print(paste('Increase in monthly gun sales in Missouri =', round(missouri.avg_post_2008 - missouri.avg_pre_2007, digits=2)))

out_data %>% select(year,month,guns_total,guns_total_seas,handgun_share,longgun_share,new_jersey,maryland,georgia,louisiana,mississippi,missouri,dc_handguns_per_100k_national_sales) %>%
    write.csv('out/all-data.csv', row.names=F)

out_data %>% plot_gunsales(savePlots=T)
