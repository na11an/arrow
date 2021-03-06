# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

import numpy as np
import pandas as pd
import pandas.util.testing as tm

import pyarrow as pa


class PandasConversionsBase(object):
    def setup(self, n, dtype):
        if dtype == 'float64_nans':
            arr = np.arange(n).astype('float64')
            arr[arr % 10 == 0] = np.nan
        else:
            arr = np.arange(n).astype(dtype)
        self.data = pd.DataFrame({'column': arr})


class PandasConversionsToArrow(PandasConversionsBase):
    param_names = ('size', 'dtype')
    params = ((10, 10 ** 6), ('int64', 'float64', 'float64_nans', 'str'))

    def time_from_series(self, n, dtype):
        pa.Table.from_pandas(self.data)


class PandasConversionsFromArrow(PandasConversionsBase):
    param_names = ('size', 'dtype')
    params = ((10, 10 ** 6), ('int64', 'float64', 'float64_nans', 'str'))

    def setup(self, n, dtype):
        super(PandasConversionsFromArrow, self).setup(n, dtype)
        self.arrow_data = pa.Table.from_pandas(self.data)

    def time_to_series(self, n, dtype):
        self.arrow_data.to_pandas()


class ToPandasStrings(object):

    param_names = ('uniqueness', 'total')
    params = ((0.001, 0.01, 0.1, 0.5), (1000000,))
    string_length = 25

    def setup(self, uniqueness, total):
        nunique = int(total * uniqueness)
        unique_values = [tm.rands(self.string_length) for i in range(nunique)]
        values = unique_values * (total // nunique)
        self.arr = pa.array(values, type=pa.string())
        self.table = pa.Table.from_arrays([self.arr], ['f0'])

    def time_to_pandas_dedup(self, *args):
        self.arr.to_pandas()

    def time_to_pandas_no_dedup(self, *args):
        self.arr.to_pandas(deduplicate_objects=False)


class ZeroCopyPandasRead(object):

    def setup(self):
        # Transpose to make column-major
        values = np.random.randn(10, 100000)

        df = pd.DataFrame(values.T)
        ctx = pa.default_serialization_context()

        self.serialized = ctx.serialize(df)
        self.as_buffer = self.serialized.to_buffer()
        self.as_components = self.serialized.to_components()

    def time_deserialize_from_buffer(self):
        pa.deserialize(self.as_buffer)

    def time_deserialize_from_components(self):
        pa.deserialize_components(self.as_components)
