#!/bin/bash

#todo : HandBrakeCLI -i 01.mkv -o result.mp4 -e x264 -q 20 -B 160 --x264-preset medium --two-pass -O --turbo --subtitle "1"  --subtitle-burn "1" --srt-codeset utf8

test=0

echo "Suppression des fichiers en double dans l'historique (cela peut prendre un peu de temps)"
./deleteDuplicateFileHistory.sh

# pour pouvoir supprimer les blancs d'un string
shopt -s extglob

type avconv >/dev/null 2>&1 || { echo >&2 "I require avconv but it's not installed.  Aborting."; exit 1; }
type HandBrakeCLI >/dev/null 2>&1 || { echo >&2 "I require HandBrakeCLI but it's not installed.  Aborting."; exit 1; }
type mediainfo >/dev/null 2>&1 || { echo >&2 "I require mediainfo but it's not installed.  Aborting."; exit 1; }
type notify-send >/dev/null 2>&1 || { echo >&2 "I require notify-send but it's not installed.  Aborting."; exit 1; }
type exiftool >/dev/null 2>&1 || { echo >&2 "I require exiftool but it's not installed.  Aborting."; exit 1; }

# on vérifie si la librairie aac stable est activé (sinon on utilise la librairie native non stable)
libfdk=`avconv -codecs | grep libfdk_aac | wc -l`

# Vérifie si la vidéo a les bons codecs pour le format mp4
isMP4() 
{
    ok=1
    if [ "$1" != "AVC" ]
    then
        ok=0
    fi
    if [ "$2" != "AAC LC" ] && [ "$2" != "AC3" ] && [ "$2" != "AAC LC-SBR" ]
    then
        ok=0
    fi
    
    # même si les codecs sont bon si le profile ne l'est pas ça ne fonctionne pas
    if [ "$3" == "L5.1" ] || [ "$3" == "L5.0" ] || [ "$3" == "L1" ]
    then
        ok=0
    fi
    
    # la ps4 lit mal en 16 frames
    if [ "$4" == "16" ]
    then
        ok=0
    fi
    
    if [ "$4" == "6" ] && [ "$5" == "1920" ]
    then
        ok=0
    fi
    
    if [ "$5" == "1920" ] && [ "$6" == "1088" ]
    then
        ok=0
    fi
    
    if [ "$7" == "VFR" ] && [ "$4" == "6" ]
    then
        ok=0
    fi
    
    echo $ok
}

# Vérifie si la vidéo a les bons codecs pour le format avi
isAVI() 
{
    ok=1
    if [ "$1" != "AVC" ] && [ "$1" != "ASP" ] && [ "$1" != "XviD" ]
    then
        ok=0
    fi
    if [ "$2" != "AAC LC" ] && [ "$2" != "AC3" ] && [ "$2" != "MP3" ] && [ "$2" != "MPEG-1 Audio layer 3" ]
    then
        ok=0
    fi
    
    if [ "$3" == "Custom" ]
    then
        ok=0
    fi
    
    if [ "$4" != "0" ] && [ "$4" != "" ]
    then
        ok=0
    fi
    
    echo $ok
}

# Vérifie si la vidéo a les bons codecs pour le format mkv
isMkv() 
{
    ok=1
    if [ "$1" != "AVC" ]
    then
        ok=0
    fi
    if [ "$2" != "AAC LC" ] && [ "$2" != "AC3" ] && [ "$2" != "MP3" ]
    then
        ok=0
    fi
    
    if [ "$3" == "L5.1" ] || [ "$3" == "L5.0" ]
    then
        ok=0
    fi
    echo $ok
}

# l'argument du chemin est obligatoire
if [ $# -gt 0 ]
then
    thread=2
    force=0
    forceAc3=0
    if [ $# -gt 1 ]
    then
        if [ "$2" == "-f" ]
        then
            force=1
        elif [ "$2" == "avi" ]
	    then
	        forceAvi=1
        elif [ "$2" == "ac3" ]
	    then
	        forceAc3=1
	    elif [ "$2" == "mkv" ]
	    then
	        forceMKV=1
	    else
            thread=$2
        fi
    fi
    if [ "$3" == "copy" ] 
    then
	    v_copy=1
    fi
    
    # Parcours de tout les fichiers à partir du répertoir donné
    # find "$1" -type f | sort -n | while read i
    find "$1" -type f -printf '%h\0%d\0%p\n' | sort -t '\0' -n | awk -F '\0' '{print $3}' | while read i
    do
        # récupération de lextension du fichier
	    j=`echo $i |awk -F . '{if (NF>1) {print $NF}}'`
        
        # si c'est un fichier vidéo mp4, avi ou mkv
        if [ "$j" == "mp4" ] || [ "$j" == "avi" ] || [ "$j" == "mkv" ]
        then
            echo "$i"
            is_encoded=`cat ~/.encode_file 2> /dev/null | grep "$i"`
            encode_type=`echo "$is_encoded" | cut -f2 -d '#'`
            if [ "$is_encoded" == "" ] || [ "$force" == "1" ] || ([ "$forceAvi" == "1" ] && [ "$j" == "avi" ]) || ([ "$forceMKV" == "1" ] && [ "$j" == "mkv" ]) || ([ "$forceAc3" == "1" ] && [[ "$encode_type" == *"AC3"* ]])
            then
	        	type "$i" > /dev/null 2> /dev/null
		        if [ "$?" == "1" ]
		        then
			        echo "File $i non lisible"
			        continue
		        fi
                media=`mediainfo --fullscan "$i"`
                if [ "$media" == "" ]
                then
                    continue
                fi
                # retourne les codes vidéo et audio de la vidéo
                codec_video=`mediainfo --fullscan "$i" | grep -i "Codecs Video" | cut -f2 -d ':'`
                codec_audio=`mediainfo --fullscan "$i" | grep -i "audio codecs" | cut -f2 -d ':'`
                frame=`mediainfo --fullscan "$i" | grep -i  "Codec_Settings_RefFrames" | cut -f2 -d ':'`
                matrix=`mediainfo --fullscan "$i" | grep -i  "Codec settings, Matrix" | cut -f2 -d ':'`
                width=`mediainfo --fullscan "$i" | grep -i "Width" | cut -f2 -d ':' | head -n 1`
                height=`mediainfo --fullscan "$i" | grep -i "Height" | cut -f2 -d ':' | head -n 1`
                gcm=`mediainfo --fullscan "$i" | grep -i "Codec settings, GMC" | cut -f2 -d ':' | head -n 1`
                frame_rate_mode=`mediainfo --fullscan "$i" | grep -i "Frame rate mode" | cut -f2 -d ':' | head -n 1`
                
                
                # supprime les blanc avant et après les codecs
                codec_video=${codec_video##*( )}
                codec_audio=${codec_audio##*( )}
                frame=${frame##*( )}
                matrix=${matrix##*( )}
                width=${width##*( )}
                height=${height##*( )}
                gcm=${gcm##*( )}
                frame_rate_mode=${frame_rate_mode##*( )}
                
                hd=""
                if [ "$width" == "1920" ] && [ "$height" == "1080" ]
                then
                    hd="hd1080"
                elif [ "$width" == "1920" ] && [ "$height" == "1088" ]
                then
                    hd="hd1080"
                elif [ "$width" == "1280" ] && [ "$height" == "720" ]
                then
                    hd="hd720"
                elif [ "$width" == "640" ] && [ "$height" == "480" ]
                then
                    hd="hd480"
                fi
                echo "$width/$height = $hd"
                
                codec_profile=`mediainfo --fullscan "$i" | grep -i "Codec profile" | cut -f2 -d ':' | cut -f2 -d '@'`
                codec_profile=${codec_profile##*( )}
                
                # pour chaque format on vérifie si l'encodage est bon
                if [ "$j" == "mp4" ]
                then
                    encode=$(isMP4 "$codec_video" "$codec_audio" "$codec_profile" "$frame" "$width" "$height" "$frame_rate_mode")
                    if [ "$forceAc3" == "1" ] && [ "$codec_audio" == "AC3" ]
                    then
                        encode=0
                    fi
                fi
                
                if [ "$j" == "avi" ]
                then
                    encode=$(isAVI "$codec_video" "$codec_audio" "$matrix" "$gcm")
		            if [ "$forceAvi" == "1" ]
		            then
			            encode=0
		            fi
                fi
                
                if [ "$j" == "mkv" ]
                then
                    encode=$(isMkv "$codec_video" "$codec_audio" "$codec_profile")
                    if [ "$forceMKV" == "1" ]
		            then
			            encode=0
		            fi
                fi
           
                
                if [ "$force" == "1" ]
                then
                    encode=0
                fi
                
                file_encode_txt="$codec_video and $codec_audio"
                echo $file_encode_txt
                
                # si l'encodage n'est pas bon il faut convertire la vidéo
                if [ "$encode" == "0" ]
                then
                    # nom du fichier pour pouvoir créer le bon fichier final
                    b=`basename "$i"`
		            b=`echo ${b%.*}`
                    
                    # chemin absolu vers le fichier
                    path=$(dirname "$i")
                    
                    # le chemin du fichier de base
                    init=`echo "$path/$b.$j"`
                    
                    # le chemin du fichier final
                    to=`echo "$path/$b.mp4"`

                    #if [ "$j" == "mkv" ]
                    #then
                    #    to=`echo $path/$b.mkv`
                    #fi

                    # pour vérifier si le fichier de base et final sont les même
                    same=0
                    if [ "$init" == "$to" ]
                    then
                        # si c'est le même nom on modifie le nom du fichier final
                        # sinon le fichier de base sera écraser dès le début et sera
                        # impossible à récupérer
                        same=1                        
                        to=`echo "$path/$b""_1.mp4"`
                        #if [ "$j" == "mkv" ]
			            #then
			            #    to=`echo "$path/$b""_1.mkv"` 
                        #fi
                    fi
                    echo "convert $init to $to"
                    
                    # conversion, on écrase si le fichier final existe
                    # En effet si l'on a coupé une conversion le fichier final sera encore présent
                    if [ $test -eq 0 ]
                    then

                        # 2 cpu utilisés
                        # les metadatas pour forcer un titre propre pour les clients
                        # la taille de la vidéo (1080p, 720p, 480p, autres)
                        # crf 19 pour une qualité d'encodage plutot bonne
                        # tune pour précisé que c'est de l'animation et donc avoir un encodage optimisé
                        # profile pour précisé le profile du format High@L3.1 
                        # level qui correspond au profile
                        # codec vidéo avc x264
                        # codec audio acc (encore en mode experimental mais libre de droit donc lisible sur tout support)
                        file_encode_txt="AVC and AAC LC"
                        start=`date +%s`
                        if [ "$j" == "mkv" ]
                        then
                            echo "HandBrakeCLI -i \"$init\" -o \"$to\" -e x264 -q 20 -B 160 --x264-preset medium --two-pass -O --turbo --subtitle \"1\"  -E av_aac --encoder-tune \"animation\" --encoder-profile \"high\" --encoder-level \"3.1\" -x ref=4:frameref=4:threads=2 --subtitle-burn \"1\" --srt-codeset utf8"
                            echo "" | HandBrakeCLI -i "$init" -o "$to" -e x264 -q 20 -B 160 --x264-preset medium --two-pass -O --turbo --subtitle "1"  -E av_aac --encoder-tune "animation" --encoder-profile "high" --encoder-level "3.1" -x ref=4:frameref=4:threads=2 --subtitle-burn "1" --srt-codeset utf8
                        else
                            if [ "$hd" == "" ]
                            then
                                if [ $libfdk -gt 0 ]
                                then
                                    if [ "$v_copy" == "1" ] && [ "$forceAc3" == "1" ] && [ "$codec_audio" == "AC3" ]
                                    then
                                        echo "avconv -y -i \"$init\" -threads $thread -c:v copy -c:a libfdk_aac \"$to\""
                                        avconv -y -i "$init" -threads -c:v copy -c:a libfdk_aac "$to"
                                    else
                                        echo "avconv -y -i \"$init\" -threads $thread -metadata title=\"$b\" -crf 19 -tune animation -profile:v high -level 31 -c:v h264 -refs 4 -c:s ssa -c:a libfdk_aac \"$to\""
                                        avconv -y -i "$init" -threads $thread -metadata title="$b" -crf 19 -tune animation -profile:v high -level 31 -c:v h264 -refs 4 -c:s ssa -c:a libfdk_aac "$to"
                                    fi
                                else
                                    if [ "$v_copy" == "1" ] && [ "$forceAc3" == "1" ] && [ "$codec_audio" == "AC3" ]
                                    then
                                        echo "avconv -y -i \"$init\" -threads $thread -c:v copy -c:a aac -strict experimental \"$to\""
                                        avconv -y -i "$init" -threads $thread -c:v copy -c:a aac -strict experimental "$to"
                                    else
                                        echo "avconv -y -i \"$init\" -threads $thread -metadata title=\"$b\" -crf 19 -tune animation -profile:v high -level 31 -c:v h264 -refs 4 -c:s ssa -c:a aac -strict experimental \"$to\""
                                        avconv -y -i "$init" -threads $thread -metadata title="$b" -crf 19 -tune animation -profile:v high -level 31 -c:v h264 -refs 4 -c:s ssa -c:a aac -strict experimental "$to"
                                    fi
                                fi
                            else
                                if [ $libfdk -gt 0 ]
                                then
                                    if [ "$v_copy" == "1" ] && [ "$forceAc3" == "1" ] && [ "$codec_audio" == "AC3" ]
                                    then
                                        echo "avconv -y -i \"$init\" -threads $thread -c:v copy -c:a libfdk_aac \"$to\""
                                        avconv -y -i "$init" -threads $thread -c:v copy -c:a libfdk_aac "$to"
                                    else
                                        echo "avconv -y -i \"$init\" -threads $thread -metadata title=\"$b\" -s:v $hd -crf 19 -tune animation -profile:v high -level 31 -c:v h264 -refs 4 -c:s ssa -c:a libfdk_aac \"$to\""
                                        avconv -y -i "$init" -threads $thread -metadata title="$b" -s:v $hd -crf 19 -tune animation -profile:v high -level 31 -c:v h264 -refs 4 -c:s ssa -c:a libfdk_aac "$to"
                                    fi
                                else
                                    if [ "$v_copy" == "1" ] && [ "$forceAc3" == "1" ] && [ "$codec_audio" == "AC3" ]
                                    then
                                        echo "avconv -y -i \"$init\" -threads $thread -c:v copy -c:a aac -strict experimental \"$to\""
                                        avconv -y -i "$init" -threads $thread -c:v hcopy -c:a aac -strict experimental "$to"
                                    else
                                        echo "avconv -y -i \"$init\" -threads $thread -metadata title=\"$b\" -s:v $hd -crf 19 -tune animation -profile:v high -level 31 -c:v h264 -refs 4 -c:s ssa -c:a aac -strict experimental \"$to\""
                                        avconv -y -i "$init" -threads $thread -metadata title="$b" -s:v $hd -crf 19 -tune animation -profile:v high -level 31 -c:v h264 -refs 4 -c:s ssa -c:a aac -strict experimental "$to"
                                    fi
                                fi
                            fi
                        fi
                       
                        # status de la commande avconv
                        code=$?
                        end=`date +%s`
                        runtime=$((end-start))

                        echo "result code : $code in $runtime seconds"
                        
                        # si la conversion à fonctionné
                        if [ $code -eq 0 ] 
                        then
                            if [ "$j" == "mkv" ]
                            then
                                exiftool -overwrite_original -all= "$to"
                            fi
                                
                            # si c'est le même fichier que la base on fait un simple mv
                            # sinon on supprime le fichier de base devenu inutile
                            if [ "$same" == "1" ]
                            then
                                hist=`grep -rne "$init" ~/.encode_file | cut -f1 -d ':'`
                                if [ "$hist" != "" ]
                                then
                                    sed -i $hist'd' ~/.encode_file
                                fi
                                echo "$init#$file_encode_txt#$hd" >> ~/.encode_file
                                echo "mv $to $init"
                                mv "$to" "$init"
                            else
                                hist=`grep -rne "$to" ~/.encode_file | cut -f1 -d ':'`
                                if [ "$hist" != "" ]
                                then
                                    sed -i $hist'd' ~/.encode_file
                                fi
                                echo "$to#$file_encode_txt#$hd" >> ~/.encode_file
                                echo "rm $init"
                                rm "$init"
                            fi
                            notify-send "convertion de $init terminée en $runtime secondes"
                        else
                            # probleme d'encodage du son apparement
                            if ([ $code -eq 134 ] || [ $code -eq 139 ]) && [ "$forceAc3" == "0" ]
                            then
                                notify-send "erreur d'encodage $init reessai avec codec AC3 après $runtime secondes"
                                file_encode_txt="AVC and AC3"
                                start=`date +%s`
                                if [ "$j" == "mkv" ]
                                then
                                    echo "HandBrakeCLI -i \"$init\" -o \"$to\" -e x264 -q 20 -B 160 --x264-preset medium --two-pass -O --turbo --subtitle \"1\"  -E av_aac --encoder-tune \"animation\" --encoder-profile \"high\" --encoder-level \"3.1\" -x ref=4:frameref=4:threads=2 --subtitle-burn \"1\" --srt-codeset utf8"
                                    echo "" | HandBrakeCLI -i "$init" -o "$to" -e x264 -q 20 -B 160 --x264-preset medium --two-pass -O --turbo --subtitle "1"  -E av_aac --encoder-tune "animation" --encoder-profile "high" --encoder-level "3.1" -x ref=4:frameref=4:threads=2 --subtitle-burn "1" --srt-codeset utf8
                                else
                                    if [ "$hd" == "" ]
                                    then
                                        if [ "$v_copy" == "1" ] && [ "$forceAc3" == "1" ] && [ "$codec_audio" == "AC3" ]
                                        then
                                            echo "avconv -y -i \"$init\" -threads $thread -c:v copy -c:a ac3 \"$to\""
                                            avconv -y -i "$init" -threads $thread -c:v copy -c:a ac3 "$to"
                                        else
                                            echo "avconv -y -i \"$init\" -threads $thread -metadata title=\"$b\" -crf 19 -tune animation -profile:v high -level 31 -c:v h264 -refs 4 -c:a ac3 -c:s ssa \"$to\""
                                            avconv -y -i "$init" -threads $thread -metadata title="$b" -crf 19 -tune animation -profile:v high -level 31 -c:v h264 -refs 4 -c:a ac3 -c:s ssa "$to"
                                        fi
                                    else
                                        if [ "$v_copy" == "1" ] && [ "$forceAc3" == "1" ] && [ "$codec_audio" == "AC3" ]
                                        then
                                            echo "avconv -y -i \"$init\" -threads $thread -c:v copy -c:a ac3 \"$to\""
                                            avconv -y -i "$init" -threads $thread -c:v copy -c:a ac3 "$to"
                                        else
                                            echo "avconv -y -i \"$init\" -threads $thread -metadata title=\"$b\" -s:v $hd -crf 19 -tune animation -profile:v high -level 31 -c:v h264 -refs 4 -c:a ac3 -c:s ssa \"$to\""
                                            avconv -y -i "$init" -threads $thread -metadata title="$b" -s:v $hd -crf 19 -tune animation -profile:v high -level 31 -c:v h264 -refs 4 -c:a ac3 -c:s ssa "$to"
                                        fi
                                    fi
                                fi
                                
                                code=$?
                                
                                end=`date +%s`
                                runtime=$((end-start))
                                echo "result code : $code in $runtime seconds"
                                
                                # si la conversion à fonctionné
                                if [ $code -eq 0 ] 
                                then
                                    if [ "$j" == "mkv" ]
                                    then
                                        exiftool -overwrite_original -all= "$to"
                                    fi
                                    # si c'est le même fichier que la base on fait un simple mv
                                    # sinon on supprime le fichier de base devenu inutile
                                    if [ "$same" == "1" ]
                                    then
                                        hist=`grep -rne "$init" ~/.encode_file | cut -f1 -d ':'`
                                        if [ "$hist" != "" ]
                                        then
                                            sed -i $hist'd' ~/.encode_file
                                        fi
                                        echo "$init#$file_encode_txt#$hd" >> ~/.encode_file
                                        echo "mv $to $init"
                                        mv "$to" "$init"
                                    else
                                        hist=`grep -rne "$to" ~/.encode_file | cut -f1 -d ':'`
                                        if [ "$hist" != "" ]
                                        then
                                            sed -i $hist'd' ~/.encode_file
                                        fi
                                        echo "$to#$file_encode_txt#$hd" >> ~/.encode_file
                                        echo "rm $init"
                                        rm "$init"
                                    fi
                                    notify-send "convertion de $init terminée en $runtime secondes"
                                else
                                    # en cas d'erreur on supprime le fichier final mal converti
                                    echo "rm $to"
                                    rm "$to"
                                    notify-send "convertion de $init échouée en $runtime secondes"
                                fi
                            fi
                            # en cas d'erreur on supprime le fichier final mal converti
                            echo "rm $to"
                            rm "$to"
                            if [ $code -eq 255 ]
			                then
                                notify-send "convertion de $init annulée"
                            else
                                notify-send "convertion de $init échouée"
                            fi
                        fi
                    fi
                else
		            hist=`grep -rne "$i" ~/.encode_file | cut -f1 -d ':'`
                    if [ "$hist" != "" ]
                    then
                        sed -i $hist'd' ~/.encode_file
                    fi

                    echo "$i#$file_encode_txt#$hd" >> ~/.encode_file
                fi # fin du test mauvais encodage
            else
                echo "$encode_type"
            fi
        fi # fin test du type de fichier
    done # fin de la liste des fichiers
fi # fin du test du nombre d'argument
