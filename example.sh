#!/usr/bin/env sh
#
# Create example and test files
#

for style in empty plain alpha named unsort unsortlist paragraph
do
  for n in '' '-n Spinellis'
  do
    nopt=`expr "$n" : '\(..\)'` ;\
    for u in '' -u
    do
      for c in '' -c
      do
        for r in '' -r
        do
          for k in '' -k
          do
            for R in '' -R
            do
              # Avoid -r -R clash in case insensitive filesystems
              if [ "x$R" = x-R ] ; then
                ropt=-UCR
              else
                ropt=''
              fi
              perl ${NAME}.pl -s $style $n $u -U $c $r $k $R \
                -h "Example: bib2xhtml -s $style $n $u -U $c $r $k $R" \
                example.bib eg/${style}${nopt}${u}${c}${r}${k}${ropt}.html
            done
          done
        done
      done
    done
  done
done

exit 0
