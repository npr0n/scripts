#!/bin/bash

basedir=/mnt/porn
sourcedir=$basedir/manualimport
targetdir=$basedir/autoimport
errordir=$basedir/importerrors
renamefiles=false
movefiles=false
moveonerror=false

allowedmatches=(30minutesoftorment boundgangbangs boundgods boundinpublic brutalsessions buttmachineboys devicebondage divinebitches electrosluts everythingbutt familiestied filthyfemdom footworship fuckingmachines gangbang gaybondage gayfetish hardcoregangbang hogtied kink kinkclassics kinkfeatures kinkmenclassics kinkuniversity kinkybites meninpain menonedge nakedkombat publicdisgrace sadisticrope sexandsubmission thetrainingofo theupperfloor tspussyhunters tsseduction ultimatesurrender waterbondage whippedass wiredpussy)
cookie_ct="1" # what kink.com shows. 1=both, 2=straight, 3=gay. For search use 1 here
cookies="ct=$cookie_ct"

function replaceSpaceDotFolder {
  # fix spaces in folder / file names
  find $1 -name '* *' -not -path "*_UNPACK_*" -not -path "*_FAILED_*" | while IFS= read -r f ; do mv -i "$f" "$(dirname "$f")/$(basename "$f"|tr ' ' .)" ; done
}

function renameMovLikeFolder {
  # rename .mp4 file like folder name (fixes obfuscated file names)
  find $1 -type f -name "*.mp4" -not -path "*_UNPACK_*" -not -path "*_FAILED_*" -exec bash -c ' DIR=$( dirname "{}"  ); mv "{}" "$DIR"/"${DIR##*/}".mp4 2>/dev/null' \;
}

function containsElement {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

function parseUrl {
  local mov=${1,,}

  channel=${mov%%\.*}
  if [[ "$channel" == "kink" ]]; then channel=""; fi ##special case for channel kink, used as placeholder for all channels in search. therefore setting to empty.
  if [ ! -z "$channel" ]; then local searchchannel="&channelIds=$channel"; else local searchchannel=""; fi

  # extract date *.YY.MM.DD.* from filename
  local date=`expr match "$mov" '.*\([0-9][0-9]\.[0-9][0-9]\.[0-9][0-9]\)'`

  # extract date format and year for search; p.e.: Mar 23, 2016
#  local year="20${date/.*/}"
  if [ ! -z "$year" ]; then local searchyear="&publishedYears=$year"; else local searchyear=""; fi
  searchdate=$(date -d"20${date//./-}" +"%b %-d, %Y")

  # extract first actor name after date
  local actor=${mov#*$date.}
  local actor=${actor/./%20}
  local actor=${actor/.*/}
  if [ ! -z "$actor" ]; then local searchactor="&q=$actor"; else local searchactor=""; fi
  # build a search url
  searchurl="https://www.kink.com/search?type=shoots$searchactor$searchchannel$searchyear&sort=published"
}

function fetchPage {
  page=$(curl -s -b "$cookies" "$1")
}

function parsePage {
  local searchstring='string(//div[normalize-space(text())="'$1'"]/ancestor::div[@class= "card-info"]//a[contains(concat(" ", @href, " "), "shoot")]/@href)'
  local shooturl=$(echo "$page" | xmllint -html -xpath "$searchstring" - 2>/dev/null)
  shootid=${shooturl##*/}
}

function getnextpageUrl {
  local searchstring='string(//nav[@class="paginated-nav"]//span[text() = "Next"]/parent::a[contains(concat(" ", @href, " "), "page")]/@href)'
  nexturl=$(echo "$page" | xmllint -html -xpath "$searchstring" - 2>/dev/null)
}

function renameMovie {
  local newname="$channel.$shootid.mp4"
  if [[ "$renamefiles" == "true" ]]; then mv $1 $newname; else echo "would REN to "$newname; fi
}

function errorMovie {
  if [[ "$moveonerror" == "true" ]]; then mv $sourcedir/$1 $errordir; else echo "would ERR to "$errordir/$1; fi
}

function moveDirectory {
  if [[ "$movefiles" == "true" ]]; then mv $sourcedir/$1 $targetdir/$2; else echo "would MOV to "$targetdir/$2; fi
}

function testvalidMatch {
  match=${1,,}
  match=${match%%\.*}
  if ! containsElement "${match}" "${allowedmatches[@]}"; then return 1; fi
}

function testalreadyRenamed {
  # returns 1 if movie contains more than one dot before .mp4
  local mov=${1%.mp4}
  local mov=${mov#*.}
  if [[ "$mov" == *"."* ]]; then return 1; fi
}

cd $sourcedir

for dir in */
do
  dir=${dir%/}

  replaceSpaceDotFolder $sourcedir/$dir

  # skip if beinning of folder name is not in matches
  if ! testvalidMatch $dir; then continue; fi

  renameMovLikeFolder $sourcedir/$dir

  # parse filename & insert id
  cd $sourcedir/$dir
  for mov in *.mp4
  do

    if ! testvalidMatch $mov; then continue; fi

    if testalreadyRenamed $mov; then continue; fi

    parseUrl $mov            # read filename and generate search url
    fetchPage $searchurl     # curl the actual html page
    parsePage "$searchdate"    # search that page for our movie id


    # if no id was found; search for Next button and fetch that page
    while [ -z $shootid ]; do
      getnextpageUrl                            # search for next page url

      if [ -z "$nexturl" ]; then break; fi     # skip if no nexturl can be found (last / only page)

      searchurl="https://www.kink.com"$nexturl  # build new searchurl
      fetchPage $searchurl   # curl the actual html page
      parsePage "$searchdate"  # search that next page for our movie id
    done

    if [ -z $shootid ]; then errorMovie $dir; continue; fi

    # rename movie
    renameMovie $mov

    # move dir
    moveDirectory $dir $channel.$shootid

  done

done
