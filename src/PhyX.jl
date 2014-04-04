# This is the file I've been writing code in whilst I try to get a grip on generating a extensible tree format.
# For now I've called this type the PhyX type.
# The type definitions are below.

type PhyXTree
	name::String
	nodes::Array{PhyXElement}
	isRooted::Bool
end


macro PhyXPopulate(attributes...)
	code = :(begin end)
	push!(code.args, :($(symbol("Label"))::String))
	push!(code.args, :($(symbol("Root"))::Bool))
	push!(code.args, :($(symbol("Tip"))::Bool))
	push!(code.args, :($(symbol("Parent"))::Int))
	for i in 1:length(attributes)
		push!(code.args, :($(symbol("@$(attributes[i])"))::$(attributes[i])))
	end
	eval(:(type PhyXElement
		$code
		PhyXElement() = new()
	end))
end

# So the basic idea is a composite type called PhyXTree which posseses a name, a bool of wether it is rooted or not.
# The nodes array contains sructures of the PhyXElement type. This is where the magic happens - each tip and clade  of the tree is represented by one of these.
# Just as in PhyX all the tips and the internal nodes/clades are contained within the <clade></clade> tags. 
# The PhyXElement type is generated by the macro PhyXPopulate, which can accept a series of types, for example "Array{Nucleotide}".
# The macro will take the types provided, and extend the PhyXElement definition to accomodate the additional types.
# An example I used that would work copying and pasting in a Julia session is - say I wanted each element to be able to possibly hold fitness values. This might be data from expriment,
# in which case probably only the PhyXElements defining the tips will end up containing such data, or perhaps a phylogenetic/coalescent simulation results in every internl node having a value too,
# either way, something like this is possible:

type fitness
	calculatedFitness::Float
end 

@PhyXPopulate fitness

# The definition of PhyXElement will now contain "Label", "Root", "Tip", "Parent", and "@fitness".
# The macro takes the name of the type, put's an @ symbol in front of it to generate a name - In my mind @fitness or @sequence,
# Is like some shorthand for "additional attribute, called fitness" - perhaps we should allow user definition fo what to call the field containing the new type.
# This is the basic idea, I think what we do to make this easier is provide a Extension class, the user put's the name of the type they want to add,
# and also how to read/write to PHyXML and NEXUS format. Then this is used with the macro to extend both the PhyXElement, and also functions for PhyXML and NEXUS format.

type PhyXtension
	typeToAdd::String
	howToRead
	howToWrite	
end

# The fields how to read and how to write could be dictionaries with the keys being the format like "NEXUS", "PhyXML" and so on.
# The values are then functions or code that are to be used by the macro to extend how the aded type is written and read to file.
# These functions I guess will largely map the fields of the new added type into a character string that is to be written to file or read from file.


# Below now are just some ideas and code I wrote playing around with LightXML reading in PhyloXML files. The recursive build function,
# Recusrively adds clades to the tree, by taking a node, reading it in, and then for every child repeats the function.
# I guess this function would need to be altered to accomodate the metaprogramming that allows types to be added for reading - so far it only reads taxonomy and seqeunce tags.
# It was made before I had the idea of making the whole thing extensible to eliminate a lot of code writing and having to write for every possible tag seen in the PhyXML documentation.




using LightXML


filepath = "/Users/axolotlfan9250/Desktop/phylodev/phyxml2"
treedoc = parse_file(filepath)

phylogenies = get_elements_by_tagname(root(treedoc), "phylogeny")

xmltree = phylogenies[1]

type Taxonomy
	IDs::Array{ID}
	Code::String
	ScientificName::String
end


# <taxonomy>
#   <id provider="ncbi">6645</id>
#   <scientific_name>Octopus vulgaris</scientific_name>
# </taxonomy>


function phyXMLbuild(xmltree)
	treestring = replace(string(xmltree), r"(\r|\n|\t)", "")
	treestring = replace(treestring, r"(\s{2,})", "")
	tstable = split(treestring, "><")
	startclade = 0
	endclade = 0
	for i in tstable
		if i == "clade"
			startclade += 1
		end
		if i == "/clade"
			endclade += 1
		end
	end
	startclade != endclade ? println("Warning! There are unequal numbers of clade begins and clade ends in this tree") : println("Current tree has $startclade clade nodes")
	# Ok the number of nodes has been established.
	Clade = Array(TestClade, startclade)		# Make an array to contain the Clade elements.
	BackTrack = zeros(Int, startclade)			# Make an array which tracks the parent of a Clade, to allow backtracking.
	Current = nodeTracker(0)                    # Start the nodetracker type.
	BackTrack[1] = 0
	XML = get_elements_by_tagname(xmltree, "clade")[1]
	recursiveBuild(XML, Clade, Current, 0)
end

function recursiveBuild(xmlclade, cladeArray, currentClade, parentClade::Int)
	# Update the node tracker.
	currentClade.nodeIndex += 1
	current = currentClade.nodeIndex # Initialize a local variable called current, taken from the currentClade variable to keep as the variable to pass to furthur recursive calls as the parent index.
	# Get name of clade element.
	name = ""
	# Get and process all additional data.... TODO
	# Process taxonomy...
	taxonomy = Taxonomy(xmlclade)
	sequences = Sequences(xmlclade)
	children = get_elements_by_tagname(xmlclade, "clade")
	# Build the clade element.
	cladeArray[currentClade.nodeIndex] = PhyXClade(name, taxonomy, sequences, parentClade)
	for i in children
		recursiveBuild(i, cladeArray, currentClade, current)
	end
end


type nodeTracker
	nodeIndex::Int
end

type ID
	provider::String
	identifier::String
end

type Accession
	Source::String
	AccessionNumber::String
end


type Sequence
	Symbol::String
	Accession::Accession
	Name::String
	MolecularSequence::String
	Annotations::Array{String}
end

taxonomy::Taxonomy
sequences::Array{Sequence}


function Sequences(xml::XMLElement)
	seqxml = get_elements_by_tagname(xml, "sequence")
	if !isempty(seqxml)
		outsequences = Array(Sequence, length(seqxml))
		for n in 1:length(seqxml)
			symbolxml = get_elements_by_tagname(seqxml[1], "symbol")
			if !isempty(symbolxml)
				symbol = content(symbolxml[1])
			else
				symbol = ""
			end
			accessionxml = get_elements_by_tagname(seqxml[1], "accession")
			if !isempty(accessionxml)
				accession = Accession(attribute(accessionxml[1], "source", required=false),content(accessionxml[1]))
			else
				accession = Accession("","")
			end
			name = get_elements_by_tagname(seqxml[1], "name")
			if !isempty(name)
				name = content(name[1])
			else
				name = ""
			end
			molseqxml = get_elements_by_tagname(seqxml[1], "mol_seq")
			if !isempty(molseqxml)
				sequence = content(molseqxml[1])
			else
				sequence = ""
			end
			annotationsxml = get_elements_by_tagname(seqxml[1], "annotation")
			if !isempty(annotationsxml)
				annotations = [attribute(i, "ref", required=false) for i in annotationsxml]
			else
				annotations = Array(String, 0)
			end
			outsequences[n] = Sequence(symbol, accession, name, sequence, annotations)
		end
		return outsequences
	else
		return Array(Sequence, 0)
	end
end


function Taxonomy(xml::XMLElement)
	taxxml = get_elements_by_tagname(xml, "taxonomy")
	if !isempty(taxxml)
		idxml = get_elements_by_tagname(taxxml[1], "id")
		if !isempty(idxml)
			idarray = [ID(attribute(i, "provider"; required=false), content(i)) for i in idxml]
		else
			idarray = Array(ID, 0)
		end
		code = get_elements_by_tagname(taxxml[1], "code")
		if !isempty(code)
			codeval = content(code[1])
		else
			codeval = ""
		end
		sciname = get_elements_by_tagname(taxxml[1], "scientific_name")
		if !isempty(sciname)
			name = content(sciname[1])
		else
			name = ""
		end
		return Taxonomy(idarray, codeval, name)
	else
		return Taxonomy(Array(ID, 0), "", "")
	end
end









	




