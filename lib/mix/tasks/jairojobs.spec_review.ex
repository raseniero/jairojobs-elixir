defmodule Mix.Tasks.Jairojobs.SpecReview do
  @shortdoc "Check that a spec was reviewed, and is consistent, before it is approved"

  @moduledoc """
  The gate before a spec is approved (`docs/README.md`, Feature lifecycle, step 1;
  constitution §6). A spec may be set to `Approved` only when this passes on the
  version put forward.

      mix jairojobs.spec_review 005

  It checks what a machine can check:

    * every requirement is in exactly one row of the Flows table;
    * every user story has a row in the screen-flow table (when the spec has
      one) and in the traceability table, and every requirement is traced;
    * each `**Serves:**` line agrees with the traceability table;
    * no two scenarios of one requirement share a name;
    * every `REQ-…` the spec mentions exists, in this spec or the one it names;
    * every diagram the spec embeds exists, has its source, and its image was
      not committed before its source last changed;
    * "Open questions" reads `- None.`;
    * the "Review before approval" section names a date and a commit, every row
      of its table has a result, and nothing in `spec.md` or the spec's diagrams
      has changed since that commit. The review section itself, the changelog
      and the `Status` / `Approved` lines may change afterwards.

  It cannot judge meaning: whether a diagram says what a scenario says, or
  whether a requirement fits the architecture. That is the reading recorded in
  the review section; this task only makes sure the record exists and is about
  the current text.

  Prints each problem and exits non-zero if there are any. Uses `git`.

  Options: `--specs-dir` (default `docs/specs`).
  """

  use Mix.Task

  @switches [specs_dir: :string]
  @review_heading "Review before approval"

  @impl Mix.Task
  def run(args) do
    {opts, numbers} = OptionParser.parse!(args, strict: @switches)
    specs_dir = Keyword.get(opts, :specs_dir, "docs/specs")

    if numbers == [] do
      Mix.raise("Give a spec number, for example: mix jairojobs.spec_review 005")
    end

    for number <- numbers, do: review(specs_dir, number)
    :ok
  end

  defp review(specs_dir, number) do
    dir = spec_dir(specs_dir, number)
    text = File.read!(Path.join(dir, "spec.md"))
    reqs = requirements(text, number)
    stories = stories(text, number)
    {reviewed, review_problems} = review_record(dir, text)

    problems =
      flows(text, number, reqs) ++
        screen_flow(text, stories) ++
        traceability(text, number, reqs, stories) ++
        scenario_names(text) ++
        references(specs_dir, text, number, reqs) ++
        diagrams(dir, text) ++
        open_questions(text) ++
        review_problems

    case problems do
      [] ->
        Mix.shell().info(
          "Spec #{number} passes the review checks (reviewed at #{reviewed}): " <>
            "#{length(reqs)} requirements, #{length(stories)} stories."
        )

      problems ->
        Enum.each(problems, &Mix.shell().error("#{number}  #{&1}"))

        Mix.raise(
          "Spec #{number} is not ready to be approved: #{length(problems)} problem(s) " <>
            "(docs/README.md, Feature lifecycle, step 1)"
        )
    end
  end

  defp spec_dir(specs_dir, number) do
    Enum.find(Path.wildcard(Path.join(specs_dir, "#{number}-*")), &File.dir?/1) ||
      Mix.raise("No spec found for #{number} in #{specs_dir}")
  end

  ## What the spec declares

  # Requirement ids from the `### REQ-…:` headings, without dropped ones.
  defp requirements(text, number) do
    for [_, id, title] <- Regex.scan(~r/^###\s+(REQ-#{number}-\d+):(.*)$/m, text),
        not String.contains?(title, "(dropped"),
        do: id
  end

  defp stories(text, number) do
    for [_, id, rest] <- Regex.scan(~r/^\*\*(US-#{number}-\d+)\*\*(.*)$/m, text),
        not String.contains?(rest, "(dropped"),
        do: id
  end

  # The body of a `## Heading` section, up to the next `## ` heading.
  defp section(text, heading) do
    case Regex.run(~r/^## #{Regex.escape(heading)}[^\n]*\n(.*?)(?=^## |\z)/ms, text) do
      [_, body] -> body
      nil -> nil
    end
  end

  defp table_rows(nil), do: []

  defp table_rows(body) do
    for line <- String.split(body, "\n"),
        String.starts_with?(String.trim_leading(line), "|"),
        cells = line |> String.trim() |> String.trim("|") |> String.split("|"),
        cells = Enum.map(cells, &String.trim/1),
        not Enum.all?(cells, &(&1 =~ ~r/^:?-+:?$/)),
        do: cells
  end

  # "REQ-005-2, -3, -4" and "REQ-005-2, REQ-005-3" both give the full ids.
  defp req_ids(cell, number) do
    for [_, id] <- Regex.scan(~r/(?:REQ-#{number})?-(\d+)\b/, cell), do: "REQ-#{number}-#{id}"
  end

  ## The checks

  defp flows(text, number, reqs) do
    rows = text |> section("Flows") |> table_rows()
    covered = Enum.flat_map(rows, fn row -> req_ids(Enum.at(row, 1, ""), number) end)

    for req <- reqs, count = Enum.count(covered, &(&1 == req)), count != 1 do
      "#{req} is in #{count} rows of the Flows table; it must be in exactly one"
    end
  end

  defp screen_flow(text, stories) do
    case section(text, "Screen flow") do
      nil ->
        []

      body ->
        rows = table_rows(body)

        for story <- stories, not Enum.any?(rows, &row_names?(&1, story)) do
          "#{story} has no row in the screen-flow table"
        end
    end
  end

  defp row_names?([first | _], id), do: first =~ ~r/^#{Regex.escape(id)}\b/
  defp row_names?([], _id), do: false

  defp traceability(text, number, reqs, stories) do
    traced =
      for [story | cells] <- text |> section("Traceability") |> table_rows(),
          story =~ ~r/^US-#{number}-\d+$/,
          into: %{},
          do: {story, cells |> Enum.join(",") |> req_ids(number)}

    serves =
      for [_, req, body] <-
            Regex.scan(~r/^###\s+(REQ-#{number}-\d+):.*?\n(.*?)(?=^###? |\z)/ms, text),
          req in reqs,
          [_, line] <- [Regex.run(~r/^\*\*Serves:\*\*(.*)$/m, body) || [nil, ""]],
          into: %{},
          do: {req, for([id] <- Regex.scan(~r/US-#{number}-\d+/, line), do: id)}

    untraced_stories =
      for story <- stories, not Map.has_key?(traced, story) do
        "#{story} has no row in the traceability table"
      end

    untraced_reqs =
      for req <- reqs, not Enum.any?(traced, fn {_story, list} -> req in list end) do
        "#{req} is in no row of the traceability table"
      end

    serves_not_traced =
      for {req, served} <- serves, story <- served, req not in Map.get(traced, story, []) do
        "#{req} serves #{story}, but the traceability table does not list it under #{story}"
      end

    traced_not_served =
      for {story, list} <- traced, req <- list, story not in Map.get(serves, req, []) do
        "the traceability table lists #{req} under #{story}, but its Serves line does not"
      end

    untraced_stories ++ untraced_reqs ++ Enum.sort(serves_not_traced ++ traced_not_served)
  end

  defp scenario_names(text) do
    text
    |> String.split("\n")
    |> Enum.reduce({nil, []}, fn line, {req, found} ->
      cond do
        match = Regex.run(~r/^###\s+(REQ-\d+-\d+):/, line) ->
          {Enum.at(match, 1), found}

        String.starts_with?(line, "## ") ->
          {nil, found}

        match = req && Regex.run(~r/^\s*Scenario:\s*(.+?)\s*$/, line) ->
          {req, [{req, normalize(Enum.at(match, 1))} | found]}

        true ->
          {req, found}
      end
    end)
    |> elem(1)
    |> Enum.frequencies()
    |> Enum.filter(fn {_key, count} -> count > 1 end)
    |> Enum.sort()
    |> Enum.map(fn {{req, name}, _count} -> "#{req} has two scenarios named \"#{name}\"" end)
  end

  defp normalize(text), do: text |> String.downcase() |> String.split() |> Enum.join(" ")

  # Every REQ id written out in full must exist where it says it does.
  defp references(specs_dir, text, number, reqs) do
    mentioned =
      for([_, spec, n] <- Regex.scan(~r/REQ-(\d{3})-(\d+)/, text), do: {spec, "REQ-#{spec}-#{n}"})
      |> Enum.uniq()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    for {spec, ids} <- Enum.sort(mentioned),
        known = known_requirements(specs_dir, spec, number, reqs, text),
        id <- Enum.sort(ids),
        id not in known do
      "#{id} is mentioned, but spec #{spec} has no such requirement"
    end
  end

  # For this spec, dropped requirements still exist; for another, read its headings.
  defp known_requirements(_specs_dir, number, number, _reqs, text) do
    for [_, id] <- Regex.scan(~r/^###\s+(REQ-#{number}-\d+):/m, text), do: id
  end

  defp known_requirements(specs_dir, spec, _number, _reqs, _text) do
    case Path.wildcard(Path.join(specs_dir, "#{spec}-*/spec.md")) do
      [path | _] ->
        for [_, id] <- Regex.scan(~r/^###\s+(REQ-#{spec}-\d+):/m, File.read!(path)), do: id

      [] ->
        []
    end
  end

  defp diagrams(dir, text) do
    links =
      for([_, link] <- Regex.scan(~r/\]\(([^)\s]+\.svg)\)/, text), do: link)
      |> Enum.uniq()
      |> Enum.sort()

    Enum.flat_map(links, fn link ->
      svg = Path.expand(link, dir)
      name = Path.basename(svg)

      cond do
        not File.exists?(svg) ->
          ["#{name} is embedded but does not exist (#{link})"]

        source = source_of(svg) ->
          if stale?(svg, source),
            do: ["#{name} is older than its source; render it again"],
            else: []

        true ->
          ["#{name} has no .puml source beside it or in ../src"]
      end
    end)
  end

  defp source_of(svg) do
    puml = Path.basename(svg, ".svg") <> ".puml"

    Enum.find(
      [
        Path.join(Path.dirname(svg), puml),
        Path.expand(Path.join("../src", puml), Path.dirname(svg))
      ],
      &File.exists?/1
    )
  end

  # The source was committed after the image, or is edited while the image is not.
  defp stale?(svg, source) do
    committed_after?(source, svg) or (dirty?(source) and not dirty?(svg))
  end

  # True when the last commit to change `later` came after the last one to change
  # `earlier`. Asked of the history, not of the clock: two commits can share a second.
  defp committed_after?(later, earlier) do
    with {:ok, a} when a != "" <- last_commit(later),
         {:ok, b} when b != "" <- last_commit(earlier),
         true <- a != b do
      match?({:ok, _}, git(Path.dirname(later), ["merge-base", "--is-ancestor", b, a]))
    else
      _ -> false
    end
  end

  defp last_commit(path) do
    git(Path.dirname(path), ["log", "-1", "--format=%H", "--", Path.basename(path)])
  end

  defp dirty?(path) do
    git(Path.dirname(path), ["status", "--porcelain", "--", Path.basename(path)]) not in [
      {:ok, ""},
      :error
    ]
  end

  defp open_questions(text) do
    body =
      (section(text, "Open questions") || "")
      |> String.replace(~r/<!--.*?-->/s, "")
      |> String.trim()

    if body == "- None.",
      do: [],
      else: ["Open questions must read \"- None.\" before approval; move answers to Decisions"]
  end

  ## The record of the review

  defp review_record(dir, text) do
    case section(text, @review_heading) do
      nil ->
        {nil, ["there is no \"#{@review_heading}\" section (copy it from the spec template)"]}

      body ->
        empty_rows =
          for [what, result | _] <- body |> String.replace(~r/<!--.*?-->/s, "") |> table_rows(),
              what != "Checked against",
              result == "" do
            "#{@review_heading}: \"#{what}\" has no result"
          end

        case Regex.run(
               ~r/^\*\*Reviewed:\*\*\s*(\d{4}-\d{2}-\d{2}) at commit `([0-9a-f]{7,40})`/m,
               body
             ) do
          [_, _date, sha] ->
            {sha, empty_rows ++ changed_since(dir, text, sha)}

          nil ->
            {nil,
             empty_rows ++
               [
                 "#{@review_heading}: no line \"**Reviewed:** YYYY-MM-DD at commit `<sha>`\""
               ]}
        end
    end
  end

  defp changed_since(dir, text, sha) do
    case git(dir, ["show", "#{sha}:./spec.md"]) do
      :error ->
        ["#{@review_heading}: commit #{sha} does not exist, or has no spec.md for this spec"]

      {:ok, then} ->
        spec = if stable(then) == stable(text), do: [], else: ["spec.md"]

        diagrams =
          case git(dir, ["status", "--porcelain", "--", "diagrams"]) do
            {:ok, ""} ->
              case git(dir, ["diff", "--name-only", sha, "--", "diagrams"]) do
                {:ok, ""} -> []
                {:ok, names} -> names |> String.split("\n") |> Enum.map(&Path.basename/1)
                :error -> []
              end

            {:ok, lines} ->
              for line <- String.split(lines, "\n"),
                  do: line |> String.slice(3..-1//1) |> Path.basename()

            :error ->
              []
          end

        case spec ++ diagrams do
          [] ->
            []

          changed ->
            [
              "#{@review_heading}: changed since the reviewed commit #{sha}: " <>
                Enum.join(changed, ", ") <> ". Review again and name the new commit"
            ]
        end
    end
  end

  # The spec without the parts that may change after the review.
  defp stable(text) do
    text
    |> String.replace(~r/^## #{Regex.escape(@review_heading)}[^\n]*\n.*?(?=^## |\z)/ms, "")
    |> String.replace(~r/^## Changelog[^\n]*\n.*\z/ms, "")
    |> String.replace(~r/^\*\*(Status|Approved):\*\*[^\n]*\n/m, "")
    |> String.replace(~r/\n{2,}/, "\n\n")
    |> String.trim()
  end

  defp git(dir, args) do
    case System.cmd("git", ["-C", dir] ++ args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      _ -> :error
    end
  end
end
