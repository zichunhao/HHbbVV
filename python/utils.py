import vector
from hist import Hist


def make_vector(events: dict, name: str, mask=None):
    """
    Creates Lorentz vector from input events and beginning name, assuming events contain {name}Pt, {name}Phi, {name}Eta, {Name}Msd variables
    Optional input mask to select certain events

    Args:
        events (dict): dict of variables and corresponding numpy arrays
        name (str): object string e.g. ak8FatJet
        mask (bool array, optional): array selecting desired events

    """

    if mask is None:
        return vector.array({
                                "pt": events[f'{name}Pt'],
                                "phi": events[f'{name}Phi'],
                                "eta": events[f'{name}Eta'],
                                "M": events[f'{name}Msd'] if f'{name}Msd' in events else events[f'{name}Mass'],
                            })
    else:
        return vector.array({
                                "pt": events[f'{name}Pt'][mask],
                                "phi": events[f'{name}Phi'][mask],
                                "eta": events[f'{name}Eta'][mask],
                                "M": events[f'{name}Msd'][mask] if f'{name}Msd' in events else events[f'{name}Mass'][mask],
                            })


def getParticles(particle_list, particle_type):
    """
    Finds particles in `particle_list` of type `particle_type`

    Args:
        particle_list: array of particle pdgIds
        particle_type: can be 1) string: 'b', 'V' or 'H' currently, or TODO: 2) pdgID, 3) list of pdgIds
    """

    B_PDGID = 5
    Z_PDGID = 23
    W_PDGID = 24

    if particle_type == 'b':
        return abs(particle_list) == B_PDGID
    elif particle_type == 'V':
        return (abs(particle_list) == W_PDGID) + (abs(particle_list) == Z_PDGID)


def singleVarHist(events, var, bins, label, weight_key='weight'):
    keys = list(events.keys())

    h = (
        Hist.new
        .StrCat(keys, name='Sample')
        .Reg(*bins, name=var, label=label)
        .Double()
    )

    for key in keys:
        h.fill(Sample=key, **{var: events[key][var]}, weight=events[key][weight_key])

    return h