# distutils: language = c++
# cython: boundscheck = False

import networkx as nx
from collections.abc import Iterable
from .utils import relabel_inv_line_graph
import numpy as np
cimport numpy as np
from numpy cimport ndarray, float64_t, int_t
#
from cpython cimport dict
import cython
from libcpp cimport bool as cpp_bool
from libcpp.map cimport map as cpp_map
from libcpp.vector cimport vector as cpp_vector
from libcpp.utility cimport pair as cpp_pair


from cython.operator cimport dereference as deref
from cython.operator cimport preincrement as preinc

ctypedef cpp_pair[int, int] cpp_edge
ctypedef cpp_vector[cpp_edge] cpp_neighbourhood
ctypedef cpp_map[cpp_edge, cpp_neighbourhood] cpp_adjacency_map
ctypedef cpp_pair[cpp_edge, cpp_neighbourhood] cpp_adjacency_map_item
ctypedef cpp_map[cpp_edge, int] cpp_attr_map
ctypedef cpp_pair[cpp_edge, int] cpp_attr_map_item

cdef int DEFAULT_DIM = 10
cdef int DEFAULT_LABEL = 0



#cdef cpp_vertex_vector get_vertex(dict attrs):
#    cdef cpp_vertex_vector res = attrs.keys()
#    return res

cdef class GraphWrapper(object):

    cdef:
        cpp_adjacency_map _graph
        cpp_attr_map _vertex_attr
        cpp_neighbourhood _vertex
        

    def __init__(self, dim=DEFAULT_DIM, gr=None, default_label=DEFAULT_LABEL):
        """Initialize Graph Wrapper object
        This is a wrapper over a networkx graph

        The graph model is based on line graph:
        the observed graph is transformed to its
        corresponding line graph.

        Consequently, observed edges are nodes (in line graph)
        and observed nodes bridging two edges are edges (in line graph).

        Keyword Arguments:
            dim {int} -- dimension of initial graph (default: {DEFAULT_DIM})
                         a complete graph dimensionned by dim is initiated
                         if no graph is passed (grap argument is None)
            gr {networkx.Graph} -- input graph (default: {None})
        """
        if dim is None:
            self._graph = cpp_adjacency_map()
            self._vertex_attr = cpp_attr_map()
            self._vertex = cpp_neighbourhood()

        else:
            if gr is None:
                # Generate a complete graph instead
                intermed_graph = nx.complete_graph(dim)
                graph = nx.line_graph(intermed_graph)
                nx.set_node_attributes(graph, default_label, 'type')

                self._graph = nx.to_dict_of_lists(graph)
                self._vertex_attr = nx.get_node_attributes(graph, 'type')
                self._vertex = graph.nodes
            else:
                if isinstance(gr, nx.DiGraph) or isinstance(gr, nx.MultiGraph):
                    msg = "⛔️ The graph passed in argument must be a Graph,"\
                        "for wrapping DiGraph, you should use DiGraphWrapper."

                    raise TypeError(msg)

                graph = gr.copy()

                compl_graph = nx.complement(graph)
                nx.set_edge_attributes(graph, 1, 'type')

                graph.add_edges_from(compl_graph.edges(), type=default_label)

                attr = nx.get_edge_attributes(graph, 'type')

                is_key_iterable = all([isinstance(key, Iterable)
                                       for key in attr.keys()])

                if is_key_iterable:
                    attr = {tuple(sorted(key)): val for key,
                            val in attr.items()}

                graph = nx.line_graph(graph)
                nx.set_node_attributes(graph, attr, 'type')

                self._graph = nx.to_dict_of_lists(graph)
                self._vertex_attr = nx.get_node_attributes(graph, 'type')
                self._vertex = graph.nodes

    def copy(self):
        copy = GraphWrapper(dim=None)
        copy.graph = self.graph.copy()
        copy.vertex = self.vertex.copy()
        return copy

    @property
    def vertex(self):
        return self._vertex_attr

    @vertex.setter
    def vertex(self, new_ver):
        self._vertex_attr = new_ver

    @property
    def graph(self):
        """Returns the Networkx graph corresponding to the graph model

        Returns:
            nx.Graph -- Corresponding graph
        """

        return self._graph

    @graph.setter
    def graph(self, new_gr):
        self._graph = new_gr

    #def get_initial_graph(self):
    #    graph = nx.from_dict_of_lists(self.graph)
    #    inv_line = nx.inverse_line_graph(graph)
    #    origin = relabel_inv_line_graph(inv_line)
#
    #    edges_to_rm = self.get_disabled_edges()
    #    origin.remove_edges_from(edges_to_rm)
    #    return origin

    def get_initial_dim(self):
        """Returns the dimension of the initial graph

        Returns:
            int -- Dimension of the initial graph
        """

        graph = nx.from_dict_of_lists(self.graph)
        return len(nx.inverse_line_graph(graph))

    cpdef get_none_edge_count(self):
        """Return the number of nodes labelled as none edge

        Returns:
            int -- number of none 'edges'
        """
        return len(self.get_disabled_edges())

    cpdef get_edge_count(self):
        """Return the number of nodes labelled as directed edge / edge

        Returns:
            int -- number of directed 'edges'
        """

        return len(self.get_enabled_edges())

    cpdef cpp_neighbourhood get_elements(self):
        """Get de list of line graph nodes
        -> edges of the initial graph representation

        Returns:
            List[EdgeId] -- list of edge identifiers (tuple)
        """

        return self._vertex

    cpdef int get_edge_type(self, cpp_edge edge_id):
        """Given an edge id
        return its corresponding type

        Arguments:
            edge_id {EdgeId} -- Edge identifier

        Returns:
            int -- Edge type
        """
        return deref(self._vertex_attr.find(edge_id)).second

    cpdef cpp_bool is_active_edge(self, cpp_edge edge_id):
        """Returns True if the edge referred by edge_id
        is active (i.e. edge_type != 0)
        False otherwise

        Arguments:
            edge_id {EdgeId} -- Edge identifier

        Returns:
            bool -- True if the edge is active
                    False otherwise
        """
        return self.get_edge_type(edge_id) != 0

    cpdef get_enabled_edges(self):
        return [k for k, e in self.vertex.items() if e != 0]

    cpdef get_disabled_edges(self):
        return [k for k, e in self.vertex.items() if not e]

    cpdef set_edge_type(self, cpp_edge edge_id, int new_val):
        """Givent an edge id
        set a new value of its corresponding type

        Arguments:
            edge_id {edgeId} -- Edge identifier
            new_val {int} -- New value
        """

        try:
            val = int(new_val)
        except ValueError:
            msg = "🤯 Edge Type must be an integer"
            raise TypeError(msg)

        self._vertex_attr[edge_id] = val

    cpdef cpp_neighbourhood get_edge_neighbourhood(self, cpp_edge edge):
        """Get the neighbourhood of the edge
        All edges connected to 'edge'

        Arguments:
            edge {edgeId} -- Edge identfier

        Returns:
            List[EdgeId] -- Neighbours
        """

        # Returns only active edge in the neighborhood

        return deref(self._graph.find(edge)).second

    cpdef float get_density(self):
        enabled_edges = len(self.get_enabled_edges())
        disabled_edges = len(self.get_disabled_edges())

        if enabled_edges < 0 and disabled_edges < 0:
            return 0

        d = enabled_edges / (enabled_edges + disabled_edges)
        return d

    cpdef int get_edge_type_count(self, cpp_edge t):
        l_edges = [k for k, e in self.vertex.items() if e == t]
        return len(l_edges)

    cpdef int get_repulsion_count(self, ex_labels=None):
        count = 0

        edges = self.vertex.keys()

        for e in edges:
            count += self.get_local_repulsion_count(e,
                                                    ex_labels=ex_labels)

        return count / 2

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cpdef ndarray[double] get_interactions_count(self, inter_nbr):
        cdef ndarray[double] interactions_count = np.zeros(inter_nbr)
        cdef ndarray[double] local_count
        edges = self._vertex

        for e in edges:
            local_count = self.get_local_interaction_count(e, inter_nbr)
            interactions_count = np.add(interactions_count, local_count)


        return interactions_count / 2
    ##############################################################
    # Local statistics
    ##############################################################

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cpdef int get_local_repulsion_count(self, cpp_edge edge, ex_labels=None):

        cdef list excluded_labels = [] if ex_labels is None else list(
            ex_labels)

        cdef int ego_type = self.get_edge_type(edge)

        if ego_type in excluded_labels:
            return 0

        cdef int count = 0
        cdef cpp_neighbourhood neigh = deref(self._graph.find(edge)).second
        cdef int label

        for n in neigh:
            label = self._vertex_attr[n]
            if label != ego_type and label not in excluded_labels:
                count += 1

        return count

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cpdef ndarray[double] get_local_interaction_count(self, edge, inter_nbr):
        cdef ndarray[double] interactions_count = np.zeros(inter_nbr)
        cdef int ego_type = self.get_edge_type(edge)
        cdef cpp_neighbourhood neigh = deref(self._graph.find(edge)).second
        cdef int label

        for n in neigh:
            label = self._vertex_attr[n]
            if label != ego_type:
                idx = ego_type + label - 1
                interactions_count[idx] += 1

        return interactions_count
