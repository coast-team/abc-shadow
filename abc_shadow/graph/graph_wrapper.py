import networkx as nx
from collections.abc import Iterable

DEFAULT_DIM = 10


class GraphWrapper(object):

    def __init__(self, dim=DEFAULT_DIM, gr=None):
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
            self._graph = None

        else:
            if gr is None:
                # Generate a complete graph instead
                graph = nx.complete_graph(dim)

                self._graph = nx.line_graph(graph)
                nx.set_node_attributes(self._graph, 0, 'type')

            else:
                if isinstance(gr, nx.DiGraph) or isinstance(gr, nx.MultiGraph):
                    msg = "⛔️ The graph passed in argument must be a Graph,"\
                        "for wrapping DiGraph, you should use DiGraphWrapper."

                    raise TypeError(msg)

                graph = gr.copy()

                compl_graph = nx.complement(graph)
                nx.set_edge_attributes(graph, 1, 'type')

                graph.add_edges_from(compl_graph.edges(), type=0)

                attr = nx.get_edge_attributes(graph, 'type')

                is_key_iterable = all([isinstance(key, Iterable)
                                       for key in attr.keys()])

                if is_key_iterable:
                    attr = {tuple(sorted(key)): val for key,
                            val in attr.items()}

                graph = nx.line_graph(graph)
                nx.set_node_attributes(graph, attr, 'type')

                self._graph = graph

    def get_graph(self):
        """Returns the Networkx graph corresponding to the graph model

        Returns:
            nx.Graph -- Corresponding graph
        """

        return self._graph

    def get_initial_dim(self):
        """Returns the dimension of the initial graph

        Returns:
            int -- Dimension of the initial graph
        """

        return len(nx.inverse_line_graph(self._graph))

    def get_none_edge_count(self):
        """Return the number of nodes labelled as none edge

        Returns:
            int -- number of none 'edges'
        """
        return len(
            [e for e in nx.get_node_attributes(self._graph, 'type').values()
                if e == 0])

    def get_edge_count(self):
        """Return the number of nodes labelled as directed edge / edge

        Returns:
            int -- number of directed 'edges'
        """

        return len(
            [e for e in nx.get_node_attributes(self._graph, 'type').values()
                if e == 1])

    def get_elements(self):
        """Get de list of line graph nodes
        -> edges of the initial graph representation

        Returns:
            List[EdgeId] -- list of edge identifiers (tuple)
        """

        return self._graph.nodes()

    def get_particle(self, id):
        """Wrapper of get_edge_type method

        Arguments:
            id {EdgeId} -- Edge identifier

        Returns:
            int -- Edge type
        """

        return self.get_edge_type(id)

    def get_edge_type(self, edge_id):
        """Given an edge id
        return its corresponding type

        Arguments:
            edge_id {EdgeId} -- Edge identifier

        Returns:
            int -- Edge type
        """
        return self._graph.nodes[edge_id]['type']

    def is_active_edge(self, edge_id):
        """Returns True if the edge referred by edge_id
        is active (i.e. edge_type == 1)
        False otherwise

        Arguments:
            edge_id {EdgeId} -- Edge identifier

        Returns:
            bool -- True if the edge is active
                    False otherwise
        """

        return self.get_edge_type(edge_id) == 1

    def get_active_edges(self):
        return [e for e in self.get_elements() if self.is_active_edge(e)]

    def set_particle(self, id, new_val):
        """Wrapper of set_edge_type

        Arguments:
            id {edgeId} -- Edge identifier
            new_val int} -- New value
        """

        self.set_edge_type(id, new_val)

    def set_edge_type(self, edge_id, new_val):
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

        self._graph.nodes[edge_id]['type'] = val

    def get_edge_neighbourhood(self, edge):
        """Get the neighbourhood of the edge

        Arguments:
            edge {edgeId} -- Edge identfier

        Returns:
            List[EdgeId] -- Neighbours
        """

        # Returns only active edge in the neighborhood
        neighs = [t for t in self._graph.neighbors(
            edge) if self.is_active_edge(t)]

        return neighs

    def get_bridge_count(self, sample):
        active_edges = self.get_active_edges()
        degrees = dict(self._graph.degree(nbunch=active_edges)).values()
        return sum(degrees / 2)
