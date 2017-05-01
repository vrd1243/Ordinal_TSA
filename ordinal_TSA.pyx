
# cython: profile=False
import numpy as np
cimport numpy as np
import cython
from scipy.misc import factorial
import time
from libc.stdlib cimport qsort
import sys
import bottleneck as bn
#cdef inline double max(double a, double b): return a if a >= b else b
from numpy import linalg as LA
import sklearn
from sklearn.neighbors import NearestNeighbors

cdef extern from "math.h":
    double log(double)
#cdef extern from "math.h":
#    int factorial(int)


cdef long c_factorial(long n):
    if n<=1:
        return 1
    return n*c_factorial(n-1)

@cython.cdivision(True)
cdef double entropy(double[:] pdf):
     cdef int i;
     cdef double entropy
     cdef double prob,l2
     cdef int N = pdf.shape[0]
     entropy =0.0
     l2 = log(2.0)
     for i in range(N):
         prob = pdf[i]
         if prob>10e-15:
             entropy = entropy - prob*(log(prob)/l2)
     return entropy


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef _get_patterns_cython(
    double[:,:] array,
    int[:,:] array_mask,
    int[:,:] patt,
    int[:,:] patt_mask,
    double[:,:] weights,
    int dim,
    int step,
    int[:] fac,
    int N,
    int T,
    int w):

    cdef int n, t, k, i, j, p, tau, start, mask
    cdef double ave, var
    cdef double[:] v = np.zeros(dim, dtype='float')
    #N is the number of time series
    #T is the number of time points
    start = step*(dim-1)
    for n in range(0, N):
        for t in range(start, T):
            mask = 1
            if w==1:
                ave = 0.
            for k in range(0, dim):
                tau = k*step
                v[k] = array[t - tau, n]
                if w==1:
                    ave += v[k]
                mask *= array_mask[t - tau, n]
            if w==1:
                ave /= dim
                var = 0.
                for k in range(0, dim):
                    var += (v[k] - ave)**2
                var /= dim
# The weights are the variances across all the dimensions of an embedded point.
                weights[t-start, n] = var
            else:
                weights[t-start, n] =1.0

            if( v[0] < v[1]):
                p = 1
            else:
                p = 0
            for i in range(2, dim):
                for j in range(0, i):
                    if( v[j] < v[i]):
                        p += fac[i]
            patt[t-start, n] = p
            patt_mask[t-start, n] = mask

    return patt, patt_mask, weights


cdef  ordinal_patt_array(double[:, :] data, int[:, :] data_mask, int dim = 2, int step = 1,int weights=0):
    """Returns symbolified array of ordinal patterns.

    Each data vector (X_t, ..., X_t+(dim-1)*step) is converted to its rank
    vector. E.g., (0.2, -.6, 1.2) --> (1,0,2) which is then assigned to a
    unique integer (see Article). There are faculty(dim) possible rank vectors.

    Note that the symb_array is step*(dim-1) shorter than the original array!

    Reference: B. Pompe and J. Runge (2011). Momentary information transfer as
    a coupling measure of time series. Phys. Rev. E, 83(5), 1-12.
    doi:10.1103/PhysRevE.83.051122

    Args:
        array (array, optional): Data array of shape (time, variables).
        array_mask (bool array, optional): Data mask where False labels masked
            samples.
        dim (int, optional): Pattern dimension
        step (int, optional): Delay of pattern embedding vector.
        weights (bool, optional): Whether to return array of variances of
            embedding vectors as weights.
        verbosity (int, optional): Level of verbosity.

    Returns:
        Tuple of converted data and new length
    """

    cdef int T,N
    T = data.shape[0]
    N = data.shape[1]
    cdef int patt_time = T - step * (dim - 1)

    if dim <= 1 or patt_time <= 0:
        raise ValueError("Dim mist be > 1 and length of delay vector smaller "
                         "array length.")

    cdef double[:,:] weights_array = np.zeros((patt_time, N), dtype='float64')
    cdef int[:,:] patt = np.zeros((patt_time, N), dtype='int32')
    cdef int[:,:] patt_mask = np.zeros((patt_time, N), dtype='int32')
    #cdef int[:] fac = factorial(np.arange(10)).astype('int32')
    #time1 = time.time()
    cdef int[:] fac = np.zeros(10,dtype='int32')

    for i in range(10):
        fac[i] =c_factorial(i)
    #time2 = time.time()

    #print(time2-time1)
    #time3 = time.time()
    #cdef int[:] fac2 = factorial(np.arange(10)).astype('int32')
    #time4 = time.time()
    #print(time4-time3)
    #print(np.asarray(fac))
    #print(np.asarray(fac2))
    #sys.exit()

    #if numpy.ndim(array) == 1:
    #    T = len(array)
    #    array = array.reshape(T, 1)
    #    array_mask = array_mask.reshape(T, 1)

    # Add noise to destroy ties...
    #data += (1E-6 * data.std(axis=0)
    #          * np.random.rand(data.shape[0], data.shape[1]).astype('float64'))


    #if weights:
    (patt, patt_mask, weights_array) = _get_patterns_cython(
            data, data_mask, patt, patt_mask, weights_array, dim, step, fac, N,
            T,weights)
    #else:
    #    (patt, patt_mask, weights_array) = _get_patterns_cython(
    #        data, data_mask, patt, patt_mask, weights_array, dim, step, fac, N,
    #        T,0)
    #print(patt.shape,data.shape,dim,step,step*(dim-1))
    #sys.exit()
    #weights_array = np.asarray(weights_array)
    #patt = np.asarray(patt)
    #patt_mask = np.asarray(patt_mask)

    #if weights:
    return patt, patt_mask, patt_time, weights_array
    #else:
    #    return (patt, patt_mask, patt_time)

@cython.cdivision(True)
def embed_array(double[:,:] data, long dim, int step=1):
    
    length = data.shape[0]; 
    ea = data[0:length - step*(dim-1)];
    for j in range(2,dim+1):
        ea = np.concatenate((ea, data[(j-1)*step:length-step*(dim-j)]), axis=1);
    return ea; 

@cython.cdivision(True)
def nearest_neighbor_predict(double[:] prev, double[:,:] data, int k, nbrs):
    
    indices = nbrs.kneighbors(np.asarray(prev))[1] + 1;   
    mink      = np.asarray(data)[indices - 1];
    mink_next = np.asarray(data)[indices];
    mean = np.mean(np.mean(mink_next, axis=0), axis=0);
    print "============"
    print "Current point "
    print np.asarray(prev);
    print "Nearest neighbors" 
    print mink;
    print "Next vector "
    print mink_next;
    print "Mean "
    print  mean;

    return mean;


@cython.cdivision(True)
def compute_mase(double[:] data, double[:] pred, double[:] ref, int test_size):
    
    pred_np = np.asarray(pred);
    data_np = np.asarray(data);
    ref_np  = np.asarray(ref);

    length = len(data_np);
    return (length - 1) / test_size * np.sum(np.abs(pred_np - ref_np)) / np.sum(np.abs(data_np[1:length] - data_np[:length-1]));

@cython.cdivision(True)
def k_ball_lma(double[:,:] data, double[:] prev, int test_size, int k):
# Generate predictions starting from N+1 index in the time series 
# until the entire length. For each prediction data_i+1, we look at
# k closest embedded numbers of data_i, progress each of them to the 
# next point and average them out to get data_i+1. Return the prediction
# array by getting the first index of data_i+1 for the predicted embedded
# points.
	
    data_len = data.shape[0];
    dim  = data.shape[1];
	
    pred_array = np.zeros(test_size);
    	
    nbrs = NearestNeighbors(n_neighbors=k, algorithm='ball_tree').fit(np.asarray(data[:-1]));
    
    for i in range(0, test_size):
        next_pred = nearest_neighbor_predict(prev, data, k, nbrs);
        #indices = nbrs.kneighbors(np.asarray(prev))[1] + 1;
        #mink_next = np.asarray(data)[indices];
        #next_pred = np.mean(np.mean(mink_next, axis=0), axis=0);
        pred_array[i] = next_pred[0];
        prev = next_pred;

    return pred_array;

@cython.cdivision(True)
def permutation_entropy(double[:,:] data, long dim,int step =1, int w=0):
    cdef int ii, kk, ll
    cdef int T,N
    # Set the number of samples and the total dimensions 
    T = data.shape[0]
    N = data.shape[1]
    cdef int patt_time = T - step * (dim - 1)
    cdef int[:,:] data_mask = np.ones((data.shape[0],data.shape[1]), dtype='int32')
    cdef int[:,:] permutations = np.zeros((patt_time, N), dtype='int32')
    cdef int[:,:] patt_mask = np.zeros((patt_time, N), dtype='int32')

    #if w == 1:
    permutations, patt_mask, patt_time, weights = ordinal_patt_array(data, data_mask, dim=dim, step=step,weights=w)
    #    weights = np.asarray(weights).squeeze()
    #else:
    #    permutations, patt_mask, patt_time,weights = ordinal_patt_array(data, data_mask, dim=dim, step=1, weights=False)
    #    weights = np.ones((permutations.shape[0],permutations.shape[1]), dtype='int32')


    cdef long wl_fact = c_factorial(dim)
    cdef double norm = log(wl_fact)/log(2.0)
    cdef double total = bn.nansum(weights)
    #cdef double[:] pmf = np.zeros(wl_fact)
    cdef double[:] pmf = np.zeros(wl_fact,dtype='float')
    cdef double[:] norm_pmf = np.zeros(wl_fact,dtype='float')

    cdef double weight
    #permutations = np.asarray(permutations).squeeze()
    #weights = np.asarray(weights)
    N = permutations.shape[0]
    cdef int p
    for ii in range(N):
        p = permutations[ii,0]
        pmf[p] = pmf[p] + weights[ii,0]
    for kk in range(wl_fact):
        norm_pmf[kk] = pmf[kk]/total
    return entropy(norm_pmf)/ norm

cdef int cmp_func(const void* a, const void* b) nogil:
    cdef double a_v = (<double*>a)[0]
    cdef double b_v = (<double*>b)[0]
    if a_v < b_v:
        return -1
    elif a_v == b_v:
        return 0
    else:
        return 1

cdef sort_c(double[:] a):
    # a needn't be C continuous because strides helps
    qsort(&a[0], a.shape[0], a.strides[0], &cmp_func)

#            pdf[s] =ordinal_TSA.permutation_entropy(surrogate,word_length,weights =surrogate_weights)
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef double permutation_entropy_s(int[:] permutations,double[:] weights, long word_length, int w=0, int step =1):
    cdef int ii, kk, ll,p
    cdef int N = permutations.shape[0]
    cdef long wl_fact = c_factorial(word_length)
    cdef double norm = log(wl_fact)/log(2.0)

    #time1 = time.time()
    #cdef double total = bn.nansum(weights)
    #time2 = time.time()
    #print(total,"bn time",time2-time1)
    #time3 = time.time()
    cdef  double total = 0
    for jj in range(weights.shape[0]):
        total += weights[jj]

    cdef double[:] pmf = np.zeros(wl_fact,dtype='float')
    cdef double[:] norm_pmf = np.zeros(wl_fact,dtype='float')

    for ii in range(N):
        p = permutations[ii]
        #print(ii,"perm",p)
        pmf[p] += weights[ii]
    for kk in range(wl_fact):
        norm_pmf[kk] = pmf[kk]/total
    return entropy(norm_pmf)/ norm






#@cython.wraparound(False)
#@cython.cdivision(True)
#@cython.nonecheck(False)
#@cython.boundscheck(False)
#@cython.wraparound(False)
@cython.cdivision(True)
def sig_testing_w_overlaps(double[:,:] data,int B,int B_w,int windowsize,int dim,int shift, int step=1,int w=0,double conf_level = 0.005):
    #w = windowsize
    #B = bootstrap samples, maybe 20,000
    #B_w is the bootstrap window length
    #B=10000
    #Shift is how much to move the window over by.
    cdef int num_TS=1

    cdef int patt_time = data.shape[0]-step*(dim-1)

    cdef int[:,:] data_mask = np.ones((data.shape[0],data.shape[1]), dtype='int32')

    #if w == 1:
    cdef double[:,:] weights = np.zeros((patt_time, num_TS), dtype='float')
    cdef int[:,:] permutations = np.zeros((patt_time, num_TS), dtype='int32')
    cdef int[:,:] patt_mask = np.zeros((patt_time, num_TS), dtype='int32')
    permutations, patt_mask, patt_time, weights = ordinal_patt_array(data, data_mask, dim=dim, step=step,weights=w)
    #np.random.seed(305)
    permutations = np.random.randint(0,100,patt_time, dtype='int32').reshape(patt_time,1)
    #print(permutations[0:5])
    #cdef int num_sur_windows = int(data.shape[0]/B_w)
    cdef int num_sur_windows = int((patt_time-B_w)/shift)+1
    #np.random.seed(None)
    #print(data.shape,B_w,num_sur_windows)
    #permutations = np.asarray(permutations).squeeze()
    #cdef int[:] permutations_c = permutations
    #cdef double[:] weights_c = weights
    cdef int i,s,jj,ii,kk,ll,rk,x
    #This is how many times to sample each window


    cdef int max_overlap = int(B_w/shift) +1
    cdef double[:,:,:] pdf = np.zeros((patt_time,B,max_overlap), dtype='float')
    cdef int[:] overlaps = np.zeros(patt_time,dtype='int32')

    cdef int lower_index =0#int(B*0.01)
    cdef int upper_index =0#int(B*0.99)
    cdef double[:] lower = np.zeros(patt_time,dtype='float')
    cdef double[:] upper = np.zeros(patt_time,dtype='float')

    cdef int[:] surrogate = np.zeros(windowsize,dtype='int32')
    cdef int[:] B_w_perms = np.zeros(B_w,dtype='int32')
    cdef double[:] surrogate_weights = np.zeros(windowsize,dtype='float')

    cdef double[:] B_w_weights = np.zeros(B_w,dtype='float')
    cdef int[:] r
    cdef double pe_s= 0.0
    print(num_sur_windows,"num windows")
    #Loop over each window
    for i in range(num_sur_windows):
        #time1 = time.time()
        #Then do B shuffles within that window
        left_endpoint = i*shift
        right_endpoint = left_endpoint+B_w
        if right_endpoint+shift>=patt_time:
            right_endpoint=patt_time
        #print("left to right",left_endpoint,right_endpoint)
            #sys.exit()
        for s in range(B):
            #r = np.random.randint(0,B_w,windowsize,dtype='int32')
            #timerand1 = time.time()
            r = np.random.randint(left_endpoint,right_endpoint,size=windowsize,dtype='int32')
            #r = np.arange(left_endpoint,right_endpoint,dtype='int32')
            #timerand2 = time.time()
            #total_rand_time = total_rand_time + timerand2-timerand1
            for kk in range(windowsize):
                rk = r[kk]
                surrogate[kk] = permutations[rk,0]
                surrogate_weights[kk] = weights[rk,0]
            #print(np.asarray(r),np.asarray(surrogate))
            #print(np.asarray(permutations))
            #print(np.asarray(surrogate_weights))
            #pe_s =permutation_entropy_s(permutations=surrogate,weights =surrogate_weights,word_length=dim,step=step,w=w)
            pe_s = np.asarray(surrogate).mean()
            #print(pe_s)
            for ll in range(left_endpoint,right_endpoint):
                pdf[ll,s,overlaps[ll]] =pe_s
                #print(ll,overlaps[ll])
        for ll in range(left_endpoint,right_endpoint):
            overlaps[ll] +=1
        #print(np.asarray(pdf[0]))
        #time2 =time.time()
        #print(time2-time1," to compute this window")
    #sys.exit()
    print(pdf.shape,patt_time)
    #sys.exit()
        #print(pdf)
        #np.asarray(pdf).sort()
    for x in range(patt_time):
        #print(x,patt_time)
        #print(pdf.shape)
        #print(x,(0,B),(0,overlaps[x]))
        #print(np.asarray(pdf[x,0:B,0:overlaps[x]]))
        local_slice = np.asarray(pdf[x,0:B,0:overlaps[x]])

        #print(local_slice.shape)
        local_slice = local_slice.flatten()
        #print("local_slice",local_slice)
        local_slice.sort()
        lower_index = int(conf_level*local_slice.shape[0])
        upper_index = int((1.0-conf_level)*local_slice.shape[0])

        #print("pdf0       ",np.asarray(pdf[0]).flatten())
        #print("local_slice",local_slice)



        #print("lowerI",lower_index)
        #print("upperI",upper_index)

        #print(local_slice.shape,lower_index,upper_index)
        #print(x,patt_time,pdf.shape)
        #print(local_slice[lower_index],local_slice[upper_index])
        lower[x] = local_slice[lower_index]
        upper[x] = local_slice[upper_index]
        #print()
        #if i ==num_sur_windows-1:
        #    for ii in range(left_endpoint,lower.shape[0]):
        #        lower[ii] = lower[ii]*pdf[lower_index]
        #        upper[ii]=upper[ii]*pdf[upper_index]
        #elif i ==0:
        #    for ii in range(B_w):
        #        lower[ii] = lower[ii]*pdf[lower_index]
        #        upper[ii]=upper[ii]*pdf[upper_index]
        #else:
        #    for jj in range(left_endpoint,right_endpoint):
        #        lower[jj]=lower[jj]*pdf[lower_index]
        #        upper[jj]=upper[jj]*pdf[upper_index]
        #        #lower[i*B_w:(i+1)*B_w] = lower[i*B_w:(i+1)*B_w]*pdf[lower_index]
        #        #upper[i*B_w:(i+1)*B_w] = upper[i*B_w:(i+1)*B_w]*pdf[upper_index]
        #print(pdf[lower_index],pdf[upper_index])


        #print(time2-time1," of which ",total_rand_time, "was random")
    print("lower=",np.asarray(lower))
    print("upper=",np.asarray(upper))
    return lower,upper


#@cython.wraparound(False)
#@cython.cdivision(True)
#@cython.nonecheck(False)
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def sig_testing(double[:,:] data,int B,int B_w,int windowsize,int dim, int step=1,int w=0):
    #w = windowsize
    #B = bootstrap samples, maybe 20,000
    #B_w is the bootstrap window length
    #B=10000
    cdef int num_TS=1

    cdef int patt_time = data.shape[0]-step*(dim-1)

    cdef int[:,:] data_mask = np.ones((data.shape[0],data.shape[1]), dtype='int32')

    #if w == 1:
    cdef double[:,:] weights = np.zeros((patt_time, num_TS), dtype='float64')
    cdef int[:,:] permutations = np.zeros((patt_time, num_TS), dtype='int32')
    cdef int[:,:] patt_mask = np.zeros((patt_time, num_TS), dtype='int32')
    permutations, patt_mask, patt_time, weights = ordinal_patt_array(data, data_mask, dim=dim, step=1,weights=w)

    cdef double[:] lower = np.ones(len(data),dtype='float')
    cdef double[:] upper = np.ones(len(data),dtype='float')
    cdef int num_sur_windows = int(data.shape[0]/B_w)
    #print(data.shape,B_w,num_sur_windows)
    #permutations = np.asarray(permutations).squeeze()
    #cdef int[:] permutations_c = permutations
    #cdef double[:] weights_c = weights
    cdef int i,s,jj,ii,kk
    #This is how many times to sample each window
    cdef double[:] pdf = np.zeros(B, dtype='float')
    cdef int lower_index =int(B*0.01)
    cdef int upper_index =int(B*0.99)
    cdef int rk

    cdef int[:] surrogate = np.zeros(windowsize,dtype='int32')
    cdef int[:] B_w_perms = np.zeros(B_w,dtype='int32')
    cdef double[:] surrogate_weights = np.zeros(windowsize,dtype='float')
    cdef double[:] B_w_weights = np.zeros(B_w,dtype='float')
    cdef int[:] r
    print(num_sur_windows,"num windows")
    for i in range(num_sur_windows):
        time1 = time.time()
        for s in range(B):
            r = np.random.randint(0,B_w,windowsize,dtype='int32')
            for kk in range(windowsize):
                rk = r[kk]
                surrogate[kk] = permutations[i*B_w+rk,0]
                surrogate_weights[kk] = weights[i*B_w+rk,0]
            pdf[s] =permutation_entropy_s(permutations=surrogate,weights =surrogate_weights,word_length=dim)
        np.asarray(pdf).sort()
        #sort_c(pdf)
        if i ==num_sur_windows-1:
            for ii in range(i*B_w,lower.shape[0]):
                lower[ii] = lower[ii]*pdf[lower_index]
                upper[ii]=upper[ii]*pdf[upper_index]
        else:
            for jj in range(i*B_w,(i+1)*B_w,1):
                lower[jj]=lower[jj]*pdf[lower_index]
                upper[jj]=upper[jj]*pdf[upper_index]
                #lower[i*B_w:(i+1)*B_w] = lower[i*B_w:(i+1)*B_w]*pdf[lower_index]
                #upper[i*B_w:(i+1)*B_w] = upper[i*B_w:(i+1)*B_w]*pdf[upper_index]
        #print(pdf[lower_index],pdf[upper_index])
        time2 =time.time()
        print(time2-time1)
    return lower,upper


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def windowed_permutation_entropy(double[:,:] data, int  window_size, int dim,int max_window_size=-1, int step =1, int w =0):
    cdef int i,ii, jj, kk, ll
    cdef int wl_fact = c_factorial(dim)
    cdef int T =data.shape[0]
    cdef int num_TS=1
    cdef int[:,:] data_mask = np.ones((T,num_TS), dtype='int32')
    cdef int patt_time = data.shape[0]-step*(dim-1)
    if max_window_size ==-1:
        max_window_size = window_size

    cdef double[:,:] weights = np.zeros((patt_time, num_TS), dtype='float64')
    cdef int[:,:] permutations = np.zeros((patt_time, num_TS), dtype='int32')
    cdef int[:,:] patt_mask = np.zeros((patt_time, num_TS), dtype='int32')
    permutations, patt_mask, patt_time, weights=ordinal_patt_array(data, data_mask, dim=dim,
                                                                       step=step,weights=w)
    #np.random.seed(305)
    permutations = np.random.randint(0,100,patt_time, dtype='int32').reshape(patt_time,1)
    print(permutations[0:5])


    cdef int num_windows = patt_time - max_window_size + 1
    cdef double[:] window_weighted_pes = np.zeros(num_windows,dtype='float')

    for ii in range(num_windows):
        window_weighted_pes[ii]=np.asarray(permutations[ii:ii+window_size]).mean()
    return window_weighted_pes


    cdef double norm = log(wl_fact)/log(2.0)
    cdef double total = np.asarray(weights[max_window_size-window_size:max_window_size]).sum()

    cdef double[:] pmf = np.zeros(wl_fact,dtype='float')
    cdef double[:] norm_pmf = np.zeros(wl_fact,dtype='float')
    cdef int p,calcIndex
    calcIndex = num_TS-1

    for ii in range(window_size):
        p = permutations[max_window_size-window_size+ii,calcIndex]
        pmf[p]=pmf[p]+weights[max_window_size-window_size+ii,calcIndex]

    for kk in range(wl_fact):
        norm_pmf[kk] = pmf[kk]/total
    window_weighted_pes[0]= entropy(norm_pmf)/ norm
    cdef double weightToRemove, weightToAdd
    cdef int permToRemove, permToAdd

    for jj in range(1, num_windows):
        weightToRemove = weights[max_window_size-window_size+jj-1,calcIndex]
        permToRemove = permutations[max_window_size-window_size+jj-1,calcIndex]
        weightToAdd = weights[max_window_size-window_size+jj+ window_size-1,calcIndex]
        permToAdd = permutations[max_window_size-window_size+jj+ window_size-1,calcIndex]
        total = total - weightToRemove + weightToAdd
        pmf[permToRemove] = pmf[permToRemove] - weightToRemove
        pmf[permToAdd] = pmf[permToAdd] + weightToAdd
        for kk in range(wl_fact):
            norm_pmf[kk] = pmf[kk] / total
        window_weighted_pes[jj] = entropy(norm_pmf) / norm

    return window_weighted_pes


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef step_windowed_permutation_entropy(double[:,:] data, int  window_size, int window_steps, int dim,int max_window_size=-1, int step =1, int w =0):
    cdef int i,ii, jj, kk, ll
    cdef int wl_fact = c_factorial(dim)
    cdef int T =data.shape[0]
    cdef int num_TS=1
    cdef int[:,:] data_mask = np.ones((T,num_TS), dtype='int32')
    cdef int patt_time = data.shape[0]-step*(dim-1)
    if max_window_size ==-1:
        max_window_size = window_size

    cdef double[:,:] weights = np.zeros((patt_time, num_TS), dtype='float64')
    cdef int[:,:] permutations = np.zeros((patt_time, num_TS), dtype='int32')
    cdef int[:,:] patt_mask = np.zeros((patt_time, num_TS), dtype='int32')
    permutations, patt_mask, patt_time, weights=ordinal_patt_array(data, data_mask, dim=dim,
                                                                       step=step,weights=w)

    cdef int num_windows = (patt_time - max_window_size) / window_steps + 1

    cdef double[:] window_weighted_pes = np.zeros(num_windows,dtype='float')
    cdef double norm = log(wl_fact)/log(2.0)

    # Calculate WPE of first window
    cdef double total = np.asarray(weights[max_window_size-window_size:max_window_size]).sum()
    cdef double[:] pmf = np.zeros(wl_fact,dtype='float')
    cdef double[:] norm_pmf = np.zeros(wl_fact,dtype='float')
    cdef int p,calcIndex
    calcIndex = num_TS-1

    for ii in range(window_size):
        p = permutations[max_window_size-window_size+ii,calcIndex]
        pmf[p] += weights[max_window_size-window_size+ii,calcIndex]

    for kk in range(wl_fact):
        norm_pmf[kk] = pmf[kk]/total
    window_weighted_pes[0]= entropy(norm_pmf)/ norm


    # Calculate WPE of next windows
    cdef double weightToRemove, weightToAdd
    cdef int permToRemove, permToAdd

    cdef double[:] weightwindowToRemove, weightwindowToAdd
    cdef int[:] permwindowToRemove, permwindowToAdd

    for jj in range(1, num_windows):
        weightwindowToRemove = weights[max_window_size-window_size+(jj-1)*window_steps:
                                       max_window_size-window_size+(jj-1)*window_steps+window_steps,calcIndex]
        permwindowToRemove = permutations[max_window_size-window_size+(jj-1)*window_steps:
                                          max_window_size-window_size+(jj-1)*window_steps+window_steps,calcIndex]
        weightwindowToAdd = weights[max_window_size+(jj-1)*window_steps : max_window_size+(jj-1)*window_steps+window_steps,calcIndex]
        permwindowToAdd = permutations[max_window_size+(jj-1)*window_steps : max_window_size+(jj-1)*window_steps+window_steps,calcIndex]

        for ll in range(window_steps):
            weightToRemove = weightwindowToRemove[ll]
            weightToAdd = weightwindowToAdd[ll]
            permToRemove = permwindowToRemove[ll]
            permToAdd = permwindowToAdd[ll]

            total += (weightToAdd - weightToRemove)
            pmf[permToRemove] -= weightToRemove
            pmf[permToAdd] += weightToAdd

        for kk in range(wl_fact):
            norm_pmf[kk] = pmf[kk] / total

        window_weighted_pes[jj] = entropy(norm_pmf) / norm
        
    return window_weighted_pes



@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef step_windowed_permutation_entropy_surrogates(double[:,:] data, int  window_size, int window_steps, int dim,int max_window_size=-1, int step =1, int w =0, int surr_samples = 1000):
    cdef int i,ii, jj, kk, ll, ss
    cdef int wl_fact = c_factorial(dim)
    cdef int T =data.shape[0]
    cdef int num_TS=1
    cdef int[:,:] data_mask = np.ones((T,num_TS), dtype='int32')
    cdef int patt_time = data.shape[0]-step*(dim-1)
    if max_window_size ==-1:
        max_window_size = window_size

    cdef double[:,:] weights = np.zeros((patt_time, num_TS), dtype='float64')
    cdef int[:,:] permutations = np.zeros((patt_time, num_TS), dtype='int32')
    cdef int[:,:] patt_mask = np.zeros((patt_time, num_TS), dtype='int32')
    permutations, patt_mask, patt_time, weights=ordinal_patt_array(data, data_mask, dim=dim,
                                                                       step=step,weights=w)

    cdef int num_windows = ((patt_time - max_window_size) / window_steps) + 1

    cdef double[:,:] window_weighted_pes = np.zeros((num_windows, surr_samples),dtype='float')
    cdef double norm = log(wl_fact)/log(2.0)

    # Calculate WPE of first window
    cdef double total = np.asarray(weights[max_window_size-window_size:max_window_size]).sum()
    cdef double[:] pmf = np.zeros(wl_fact, dtype='float')
    cdef double[:] norm_pmf = np.zeros(wl_fact, dtype='float')
    cdef int p,calcIndex
    calcIndex = num_TS-1

    for ii in range(window_size):
        p = permutations[max_window_size-window_size+ii,calcIndex]
        pmf[p] += weights[max_window_size-window_size+ii,calcIndex]

    for kk in range(wl_fact):
        norm_pmf[kk] = pmf[kk]/total
    window_weighted_pes[0]= entropy(norm_pmf) / norm

    # Calculate WPE of next windows
    cdef double weightToRemove, weightToAdd
    cdef int permToRemove, permToAdd

    cdef double[:] weightwindowToRemove, weightwindowToAdd
    cdef int[:] permwindowToRemove, permwindowToAdd

    for jj in range(1, num_windows):
        weightwindowToRemove = weights[max_window_size-window_size+(jj-1)*window_steps:
                                       max_window_size-window_size+(jj-1)*window_steps+window_steps,calcIndex]
        permwindowToRemove = permutations[max_window_size-window_size+(jj-1)*window_steps:
                                          max_window_size-window_size+(jj-1)*window_steps+window_steps,calcIndex]
        weightwindowToAdd = weights[max_window_size+(jj-1)*window_steps : max_window_size+(jj-1)*window_steps+window_steps,calcIndex]
        permwindowToAdd = permutations[max_window_size+(jj-1)*window_steps : max_window_size+(jj-1)*window_steps+window_steps,calcIndex]

        for ll in range(window_steps):
            weightToRemove = weightwindowToRemove[ll]
            weightToAdd = weightwindowToAdd[ll]
            permToRemove = permwindowToRemove[ll]
            permToAdd = permwindowToAdd[ll]

            total += (weightToAdd - weightToRemove)
            pmf[permToRemove] -= weightToRemove
            pmf[permToAdd] += weightToAdd

        for kk in range(wl_fact):
            norm_pmf[kk] = pmf[kk] / total

        window_weighted_pes[jj] = entropy(norm_pmf) / norm
        
    return window_weighted_pes
