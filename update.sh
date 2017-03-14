#!/bin/bash
set -eo pipefail

declare -A cmd=(
	[apache]='apache2-foreground'
	[fpm]='php-fpm'
)

# version_greater_or_equal A B returns whether A >= B
function version_greater_or_equal() {
	[[ "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1" || "$1" == "$2" ]];
}

latests=( $(curl -sSL 'https://nextcloud.com/changelog/' |tac|tac| \
	grep -o "\(Version\|Release\)\s\+[[:digit:]]\+\(\.[[:digit:]]\+\)\+" | \
	awk '{ print $2 }' | sort -V ) )

travisEnv=
for latest in "${latests[@]}"; do
	version=$(echo "$latest" | cut -d. -f1-2)

	for variant in apache fpm; do
		# Create the version+variant directory with a Dockerfile.
		mkdir -p "$version/$variant"

		template="Dockerfile.template"
		if version_greater_or_equal "$version" "11.0"; then
			template="Dockerfile-php7.template"
		fi
		cp "$template" "$version/$variant/Dockerfile"

		echo "updating $latest [$version] $variant"

		# Replace the variables.
		sed -ri -e '
			s/%%VARIANT%%/'"$variant"'/g;
			s/%%VERSION%%/'"$latest"'/g;
			s/%%CMD%%/'"${cmd[$variant]}"'/g;
		' "$version/$variant/Dockerfile"

		# Remove Apache commands if we're not an Apache variant.
		if [ "$variant" != "apache" ]; then
			sed -ri -e '/a2enmod/d' "$version/$variant/Dockerfile"
		fi

		# Copy the docker-entrypoint.
		cp docker-entrypoint.sh "$version/$variant/docker-entrypoint.sh"

		travisEnv='\n  - VERSION='"$version"' VARIANT='"$variant$travisEnv"
	done
done

# update .travis.yml
travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis"  > .travis.yml

# remove duplicate entries
echo "$(awk '!NF || !seen[$0]++' .travis.yml)" > .travis.yml
