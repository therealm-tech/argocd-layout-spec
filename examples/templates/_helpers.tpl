{{/*
Deep-merges .src into .dst in place. Maps merge recursively, anything else is
replaced, and a null removes the key (SPEC §6.2). Named templates can only
return strings, hence the mutation.
*/}}
{{- define "layout.merge" -}}
{{- $dst := .dst -}}
{{- range $k, $v := .src -}}
{{- if kindIs "invalid" $v -}}
{{- $_ := unset $dst $k -}}
{{- else if kindIs "map" $v -}}
{{- if not (kindIs "map" (index $dst $k)) -}}
{{- $_ := set $dst $k (dict) -}}
{{- end -}}
{{- include "layout.merge" (dict "dst" (index $dst $k) "src" $v) -}}
{{- else -}}
{{- $_ := set $dst $k $v -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Merges every existing file of .paths, in order, into .dst. */}}
{{- define "layout.mergeFiles" -}}
{{- $root := .root -}}
{{- $dst := .dst -}}
{{- range $path := .paths -}}
{{- $content := $root.Files.Get $path | fromYaml -}}
{{- if hasKey $content "Error" -}}
{{- fail (printf "%s: %s" $path $content.Error) -}}
{{- end -}}
{{- include "layout.merge" (dict "dst" $dst "src" $content) -}}
{{- end -}}
{{- end -}}

{{/* Fails the render when property .name is undefined (SPEC §9.2.3). */}}
{{- define "layout.requireProperty" -}}
{{- if not (hasKey .props .name) -}}
{{- fail (printf "%s: undefined property %q" .context .name) -}}
{{- end -}}
{{- end -}}

{{/* A Kustomize patch target from a resource identity (SPEC §2). */}}
{{- define "layout.target" -}}
{{- $parts := splitList "/" .identity -}}
{{- if ne (len $parts) 3 -}}
{{- fail (printf "%s: malformed resource identity %q" .context .identity) -}}
{{- end -}}
{{- $nameParts := splitList "_" (index $parts 2) -}}
{{- if ne (index $parts 0) "core" }}
group: {{ index $parts 0 }}
{{- end }}
kind: {{ index $parts 1 }}
name: {{ index $nameParts 0 }}
{{- if gt (len $nameParts) 1 }}
namespace: {{ index $nameParts 1 }}
{{- end }}
{{- end -}}

{{/*
Kustomize patches setting mapped properties (SPEC §9.3): one JSON patch per
resource, one `add` per pointer.
*/}}
{{- define "layout.patches" -}}
{{- $ctx := . -}}
{{- range $identity, $pointers := .mapping }}
- target:
    {{- include "layout.target" (dict "identity" $identity "context" $ctx.context) | trim | nindent 4 }}
  patch: |-
    {{- range $pointer, $property := $pointers }}
    - op: add
      path: {{ $pointer }}
      {{- include "layout.requireProperty" (dict "props" $ctx.props "name" $property "context" $ctx.context) }}
      value: {{ index $ctx.props $property | toJson }}
    {{- end }}
{{- end }}
{{- end -}}

{{/* The repository path of a file of the layout. */}}
{{- define "layout.repoPath" -}}
{{- $base := .root.Values.layout.path | default "." -}}
{{- if eq $base "." -}}
{{- .path -}}
{{- else -}}
{{- printf "%s/%s" (trimSuffix "/" $base) .path -}}
{{- end -}}
{{- end -}}
